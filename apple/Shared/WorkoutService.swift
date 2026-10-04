import Foundation

struct SetEntry: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var checked: Bool
}

struct ExerciseGroup: Identifiable, Equatable {
    let id: String // exercise id
    let name: String
    let note: String?
    let equipment: String?
    let videoUrl: String?
    var sets: [SetEntry]

    var isComplete: Bool { !sets.isEmpty && sets.allSatisfy { $0.checked } }
    var doneCount: Int { sets.filter { $0.checked }.count }
}

/// `select=cycle_number`-only responses don't carry the other required
/// WorkoutSession fields, so they need their own minimal decode target
/// rather than being force-fit into the full struct.
private struct CycleNumberRow: Decodable {
    let cycleNumber: Int
    enum CodingKeys: String, CodingKey { case cycleNumber = "cycle_number" }
}

/// Ports index.html's loadProgram()/finishBtn logic: same day/cycle auto-rotation,
/// same "already logged today stays pinned" behavior, same session upsert shape.
/// See CLAUDE.md for the underlying schema this talks to.
@MainActor
final class WorkoutService: ObservableObject {
    private let client: SupabaseClient

    @Published var dayOptions: [WorkoutDay] = []
    @Published var suggestedDayId: String?
    @Published var selectedDayId: String?
    @Published var selectedCycleForLookup: Int = 1
    @Published var maxCycle: Int = 1
    @Published var title: String = ""
    @Published var cycleLabel: String = ""
    @Published var groups: [ExerciseGroup] = []
    @Published var finishedToday = false
    @Published var generalNote: String = ""
    @Published var issueNote: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastSavedMessage: String?

    private var currentWorkoutDayId: String?
    // Despite the name, this holds cycleForLookup (the wrapped 1...maxCycle value) —
    // that's what the web app actually writes to sessions.cycle_number, confirmed
    // against live data. The ever-incrementing number only exists transiently while
    // computing which wrapped slot comes next.
    private var currentCycleRaw: Int = 1

    init(client: SupabaseClient) { self.client = client }

    func load(dayIdOverride: String? = nil, cycleOverride: Int? = nil) async {
        guard let userId = client.currentUserId else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let allDays: [WorkoutDay] = try await client.select(
                "workout_days",
                query: [URLQueryItem(name: "user_id", value: "eq.\(userId)"), URLQueryItem(name: "order", value: "sequence_order.asc")],
                as: [WorkoutDay].self
            )
            guard !allDays.isEmpty else { errorMessage = "No workout program found yet."; return }
            dayOptions = allDays
            let activeDays = allDays.filter { $0.active }
            let rotationDays = activeDays.isEmpty ? allDays : activeDays

            let lastSessions: [WorkoutSession] = try await client.select(
                "sessions",
                query: [
                    URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                    URLQueryItem(name: "order", value: "date.desc,created_at.desc"),
                    URLQueryItem(name: "limit", value: "1"),
                ], as: [WorkoutSession].self
            )
            let lastSession = lastSessions.first
            let today = DateUtils.todayString()
            let hasTodaySession = lastSession?.date == today
            let targetsTodaysDay = dayIdOverride == nil || (hasTodaySession && dayIdOverride == lastSession?.workoutDayId)
            let alreadyDoneToday = hasTodaySession && targetsTodaysDay && cycleOverride == nil

            var autoDay: WorkoutDay
            var autoCycle: Int
            if let lastSession {
                if hasTodaySession {
                    autoDay = allDays.first(where: { $0.id == lastSession.workoutDayId }) ?? rotationDays[0]
                    autoCycle = lastSession.cycleNumber
                } else if let lastDay = rotationDays.first(where: { $0.id == lastSession.workoutDayId }) {
                    let idx = rotationDays.firstIndex(of: lastDay)!
                    autoDay = rotationDays[(idx + 1) % rotationDays.count]
                    let prevOnNext: [CycleNumberRow] = try await client.select(
                        "sessions",
                        query: [
                            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                            URLQueryItem(name: "workout_day_id", value: "eq.\(autoDay.id)"),
                            URLQueryItem(name: "select", value: "cycle_number"),
                            URLQueryItem(name: "order", value: "cycle_number.desc"),
                            URLQueryItem(name: "limit", value: "1"),
                        ], as: [CycleNumberRow].self
                    )
                    autoCycle = (prevOnNext.first?.cycleNumber ?? 0) + 1
                } else {
                    autoDay = rotationDays[0]
                    autoCycle = 1
                }
            } else {
                autoDay = rotationDays[0]
                autoCycle = 1
            }
            suggestedDayId = autoDay.id

            var nextDay: WorkoutDay
            var nextCycle: Int
            if alreadyDoneToday, let lastSession {
                nextDay = allDays.first(where: { $0.id == lastSession.workoutDayId }) ?? autoDay
                nextCycle = lastSession.cycleNumber
            } else if let dayIdOverride, let overrideDay = dayOptions.first(where: { $0.id == dayIdOverride }) {
                nextDay = overrideDay
                if let cycleOverride {
                    nextCycle = cycleOverride
                } else {
                    let prevOnDay: [CycleNumberRow] = try await client.select(
                        "sessions",
                        query: [
                            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                            URLQueryItem(name: "workout_day_id", value: "eq.\(nextDay.id)"),
                            URLQueryItem(name: "select", value: "cycle_number"),
                            URLQueryItem(name: "order", value: "cycle_number.desc"),
                            URLQueryItem(name: "limit", value: "1"),
                        ], as: [CycleNumberRow].self
                    )
                    nextCycle = (prevOnDay.first?.cycleNumber ?? 0) + 1
                }
            } else {
                nextDay = autoDay
                nextCycle = autoCycle
            }

            let exercises: [Exercise] = try await client.select(
                "exercises",
                query: [
                    URLQueryItem(name: "workout_day_id", value: "eq.\(nextDay.id)"),
                    URLQueryItem(name: "order", value: "order_index.asc"),
                ], as: [Exercise].self
            )
            let maxCyc = max(1, exercises.flatMap { $0.cycles.map { $0.cycle } }.max() ?? 1)
            let cycleForLookup = ((nextCycle - 1) % maxCyc) + 1

            var newGroups: [ExerciseGroup] = exercises.map { ex in
                // Matches the web app exactly: look up this exercise's prescription for
                // the shared, day-level cycleForLookup; fall back to its first cycle
                // entry if it doesn't happen to have one at that exact number.
                let cyc = ex.cycles.first(where: { $0.cycle == cycleForLookup }) ?? ex.cycles.first
                let text = cyc?.prescription ?? ""
                let sets = text.isEmpty ? [] : text.split(separator: ",").map { SetEntry(text: $0.trimmingCharacters(in: .whitespaces), checked: false) }
                return ExerciseGroup(id: ex.id, name: ex.name, note: ex.notes, equipment: ex.equipment, videoUrl: ex.videoUrl, sets: sets)
            }

            currentWorkoutDayId = nextDay.id
            currentCycleRaw = cycleForLookup
            selectedDayId = nextDay.id
            selectedCycleForLookup = cycleForLookup
            maxCycle = maxCyc

            if alreadyDoneToday, let lastSession, let sessionId = lastSession.id {
                let logs: [SessionExerciseLog] = try await client.select(
                    "session_exercise_logs",
                    query: [URLQueryItem(name: "session_id", value: "eq.\(sessionId)")],
                    as: [SessionExerciseLog].self
                )
                for log in logs {
                    guard let gi = newGroups.firstIndex(where: { $0.id == log.exerciseId }) else { continue }
                    let actualSets = (log.actual ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    if !actualSets.isEmpty {
                        newGroups[gi].sets = actualSets.map { SetEntry(text: $0, checked: log.completed) }
                    } else if log.completed {
                        for i in newGroups[gi].sets.indices { newGroups[gi].sets[i].checked = true }
                    }
                }
                generalNote = lastSession.generalNote ?? ""
                issueNote = lastSession.issueNote ?? ""
            } else {
                generalNote = ""
                issueNote = ""
            }

            groups = newGroups
            title = "\(nextDay.code) · \(nextDay.name)"
            cycleLabel = "Cycle \(cycleForLookup) of \(maxCyc)"
            finishedToday = alreadyDoneToday
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleSet(groupId: String, setId: UUID) {
        guard let gi = groups.firstIndex(where: { $0.id == groupId }),
              let si = groups[gi].sets.firstIndex(where: { $0.id == setId }) else { return }
        groups[gi].sets[si].checked.toggle()
    }

    func updateSetText(groupId: String, setId: UUID, text: String) {
        guard let gi = groups.firstIndex(where: { $0.id == groupId }),
              let si = groups[gi].sets.firstIndex(where: { $0.id == setId }) else { return }
        groups[gi].sets[si].text = text
    }

    /// Mirrors finishBtn's click handler: upsert the session, replace its exercise logs.
    func save(date: String = DateUtils.todayString()) async {
        guard let userId = client.currentUserId, let dayId = currentWorkoutDayId else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let total = groups.reduce(0) { $0 + $1.sets.count }
        let done = groups.reduce(0) { $0 + $1.doneCount }
        do {
            let sessionPayload = NewWorkoutSession(
                userId: userId, workoutDayId: dayId, cycleNumber: currentCycleRaw, date: date,
                setsCompleted: done, setsTotal: total,
                generalNote: generalNote.isEmpty ? nil : generalNote,
                issueNote: issueNote.isEmpty ? nil : issueNote
            )
            let data = try await client.upsert(
                "sessions", values: sessionPayload,
                onConflict: "user_id,workout_day_id,cycle_number,date", returning: true
            )
            let savedSessions = try JSONDecoder().decode([WorkoutSession].self, from: data)
            guard let sessionId = savedSessions.first?.id else {
                errorMessage = "Saved, but couldn't confirm the session id."
                return
            }
            _ = try? await client.delete("session_exercise_logs", query: [URLQueryItem(name: "session_id", value: "eq.\(sessionId)")])
            let logs = groups.map { group in
                NewSessionExerciseLog(
                    sessionId: sessionId, exerciseId: group.id,
                    actual: group.sets.map { $0.text }.joined(separator: ", "),
                    completed: !group.sets.isEmpty && group.sets.allSatisfy { $0.checked }
                )
            }
            if !logs.isEmpty { try await client.insert("session_exercise_logs", values: logs) }
            lastSavedMessage = done == total ? "Workout logged" : "Progress saved (\(done)/\(total))"
            if date == DateUtils.todayString() { await load() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
