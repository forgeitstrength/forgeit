import SwiftUI

struct WorkoutView: View {
    @EnvironmentObject var workout: WorkoutService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = workout.errorMessage {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }

                    dayPicker

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.title).font(.title2.bold())
                        Text(workout.cycleLabel).font(.subheadline).foregroundStyle(.secondary)
                    }

                    ForEach(workout.groups) { group in
                        ExerciseGroupCard(group: binding(for: group.id))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes for today").font(.caption.bold()).foregroundStyle(.secondary)
                        TextField("How did it feel?", text: $workout.generalNote, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Text("Something off today?").font(.caption.bold()).foregroundStyle(.secondary)
                        TextField("Flags today as a one-off, skipped by auto-progression", text: $workout.issueNote, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        Task { await workout.save() }
                    } label: {
                        if workout.isLoading {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(workout.finishedToday ? "Update saved workout" : "Save workout").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(workout.isLoading)

                    if let saved = workout.lastSavedMessage {
                        Text(saved).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await workout.load() }
        }
    }

    private var dayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(workout.dayOptions) { day in
                    Button {
                        Task { await workout.load(dayIdOverride: day.id) }
                    } label: {
                        VStack(spacing: 2) {
                            Text(day.code).font(.subheadline.bold())
                            Text(day.name).font(.caption2).lineLimit(1)
                        }
                        .frame(minWidth: 56)
                        .padding(.vertical, 6).padding(.horizontal, 8)
                        .background(day.id == workout.selectedDayId ? Color.orange : Color(.secondarySystemBackground))
                        .foregroundStyle(day.id == workout.selectedDayId ? .white : .primary)
                        .opacity(day.active ? 1 : 0.5)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private func binding(for id: String) -> Binding<ExerciseGroup> {
        Binding(
            get: { workout.groups.first(where: { $0.id == id }) ?? ExerciseGroup(id: id, name: "", note: nil, equipment: nil, videoUrl: nil, sets: []) },
            set: { newValue in
                if let idx = workout.groups.firstIndex(where: { $0.id == id }) { workout.groups[idx] = newValue }
            }
        )
    }
}

private struct ExerciseGroupCard: View {
    @Binding var group: ExerciseGroup
    @State private var showDetails = false
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                if isWarmupOrFinisher, let note = group.note, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if group.note != nil || group.equipment != nil || group.videoUrl != nil {
                    DisclosureGroup("Details", isExpanded: $showDetails) {
                        VStack(alignment: .leading, spacing: 6) {
                            if let note = group.note, !note.isEmpty { Text(note).font(.footnote) }
                            if let equipment = group.equipment {
                                Label(equipment, systemImage: "dumbbell").font(.footnote).foregroundStyle(.secondary)
                            }
                            if let videoUrl = group.videoUrl, let url = URL(string: videoUrl) {
                                Link(destination: url) {
                                    Label("Watch form", systemImage: "play.circle.fill")
                                }
                                .font(.footnote.bold())
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.footnote.bold())
                }

                ForEach(group.sets) { set in
                    HStack {
                        Button {
                            if let si = group.sets.firstIndex(where: { $0.id == set.id }) {
                                group.sets[si].checked.toggle()
                            }
                        } label: {
                            Image(systemName: set.checked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(set.checked ? .green : .secondary)
                        }
                        TextField("set", text: textBinding(for: set.id))
                            .textFieldStyle(.roundedBorder)
                            .strikethrough(set.checked)
                        Button {
                            guard group.sets.count > 1, let si = group.sets.firstIndex(where: { $0.id == set.id }) else { return }
                            group.sets.remove(at: si)
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                Button {
                    group.sets.append(SetEntry(text: group.sets.last?.text ?? "", checked: false))
                } label: {
                    Label("Add set", systemImage: "plus").font(.footnote.bold())
                }
            }
            .padding(.top, 4)
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(group.name).font(.headline)
                    if !group.sets.isEmpty {
                        Text("\(group.doneCount)/\(group.sets.count) sets\(group.isComplete ? " · done" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if group.isComplete {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private func textBinding(for setId: UUID) -> Binding<String> {
        Binding(
            get: { group.sets.first(where: { $0.id == setId })?.text ?? "" },
            set: { newValue in
                if let si = group.sets.firstIndex(where: { $0.id == setId }) { group.sets[si].text = newValue }
            }
        )
    }

    private var isWarmupOrFinisher: Bool {
        group.name == "WARM-UP" || group.name.uppercased().hasPrefix("FINISHER")
    }
}
