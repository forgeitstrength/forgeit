import SwiftUI

@main
struct ForgeApp: App {
    @StateObject private var client = SupabaseClient.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(client)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var client: SupabaseClient

    var body: some View {
        Group {
            if client.isLoading {
                ProgressView()
            } else if client.isSignedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
    }
}
