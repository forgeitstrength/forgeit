import SwiftUI

struct WatchLoginView: View {
    @EnvironmentObject var client: SupabaseClient
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Forge").font(.headline)
                Text("Sign in on your iPhone first, then open this app — it reuses the same account.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("Email", text: $email)
                SecureField("Password", text: $password)

                if let errorText {
                    Text(errorText).font(.caption2).foregroundStyle(.red)
                }

                Button(isBusy ? "..." : "Log in") {
                    Task {
                        isBusy = true
                        defer { isBusy = false }
                        do { try await client.signIn(email: email, password: password) }
                        catch { errorText = error.localizedDescription }
                    }
                }
                .disabled(email.isEmpty || password.isEmpty || isBusy)
            }
            .padding()
        }
    }
}
