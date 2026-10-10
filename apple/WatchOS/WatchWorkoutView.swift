import SwiftUI

struct WatchWorkoutView: View {
    @EnvironmentObject var workout: WorkoutService

    var body: some View {
        NavigationStack {
            List {
                if let error = workout.errorMessage {
                    Text(error).font(.caption2).foregroundStyle(.red)
                }
                Section {
                    Text(workout.title).font(.headline)
                    Text(workout.cycleLabel).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(workout.groups.indices, id: \.self) { gi in
                    Section(workout.groups[gi].name) {
                        ForEach(workout.groups[gi].sets.indices, id: \.self) { si in
                            Button {
                                workout.groups[gi].sets[si].checked.toggle()
                            } label: {
                                HStack {
                                    Image(systemName: workout.groups[gi].sets[si].checked ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(workout.groups[gi].sets[si].checked ? Color.green : Color.secondary)
                                    Text(workout.groups[gi].sets[si].text)
                                        .strikethrough(workout.groups[gi].sets[si].checked)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button {
                    Task { await workout.save() }
                } label: {
                    if workout.isLoading { ProgressView() } else { Text("Save workout") }
                }
                .tint(.orange)
                .disabled(workout.isLoading)
            }
            .navigationTitle("Workout")
        }
    }
}
