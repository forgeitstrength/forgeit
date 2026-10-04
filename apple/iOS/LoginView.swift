import SwiftUI

struct LoginView: View {
    @EnvironmentObject var client: SupabaseClient
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isBusy = false
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("Forge").font(.largeTitle.bold())

                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                SecureField("Password", text: $password)
                    .textContentType(isSignUp ? .newPassword : .password)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(messageIsError ? .red : .green)
                }

                Button {
                    Task { await submit() }
                } label: {
                    if isBusy {
                        ProgressView()
                    } else {
                        Text(isSignUp ? "Create account" : "Log in")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(email.isEmpty || password.isEmpty || isBusy)

                Button(isSignUp ? "Already have an account? Log in" : "New here? Create an account") {
                    isSignUp.toggle()
                    message = nil
                }
                .font(.footnote)
            }
            .padding(24)
        }
    }

    private func submit() async {
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            if isSignUp {
                try await client.signUp(email: email, password: password)
                messageIsError = false
                message = "Account created — check your email if confirmation is required, then log in."
                isSignUp = false
            } else {
                try await client.signIn(email: email, password: password)
            }
        } catch {
            messageIsError = true
            message = error.localizedDescription
        }
    }
}
