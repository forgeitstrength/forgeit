import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var client: SupabaseClient
    @StateObject private var workout: WorkoutService
    @StateObject private var nutrition: NutritionService

    init() {
        let c = SupabaseClient.shared
        _workout = StateObject(wrappedValue: WorkoutService(client: c))
        _nutrition = StateObject(wrappedValue: NutritionService(client: c))
    }

    var body: some View {
        TabView {
            WorkoutView()
                .environmentObject(workout)
                .tabItem { Label("Workout", systemImage: "dumbbell.fill") }

            NutritionView()
                .environmentObject(nutrition)
                .tabItem { Label("Nutrition", systemImage: "fork.knife") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.orange)
        .task {
            await workout.load()
            await nutrition.loadDay()
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var client: SupabaseClient

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let email = client.session?.user.email {
                        Text(email).foregroundStyle(.secondary)
                    }
                    Button("Sign Out", role: .destructive) { client.signOut() }
                }
                Section("About") {
                    Text("Forge v1 — workout + nutrition logging, synced with the web app. Plan, Progress, and Profile editing aren't in this build yet — use the web app for those.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
