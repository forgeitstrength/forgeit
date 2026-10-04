import SwiftUI

@main
struct ForgeWatchApp: App {
    @StateObject private var client = SupabaseClient.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(client)
        }
    }
}

struct WatchRootView: View {
    @EnvironmentObject var client: SupabaseClient

    var body: some View {
        Group {
            if client.isLoading {
                ProgressView()
            } else if client.isSignedIn {
                WatchMainView()
            } else {
                WatchLoginView()
            }
        }
    }
}

struct WatchMainView: View {
    @StateObject private var workout: WorkoutService
    @StateObject private var nutrition: NutritionService

    init() {
        let c = SupabaseClient.shared
        _workout = StateObject(wrappedValue: WorkoutService(client: c))
        _nutrition = StateObject(wrappedValue: NutritionService(client: c))
    }

    var body: some View {
        TabView {
            WatchWorkoutView()
                .environmentObject(workout)
            WatchQuickLogView()
                .environmentObject(nutrition)
        }
        .tabViewStyle(.page)
        .task {
            await workout.load()
            await nutrition.loadDay()
        }
    }
}
