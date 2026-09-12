import SwiftUI

struct LoginView: View {
    @Environment(RepositoryContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var webAuth = WebAuthSession()
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(.teal)
                Text("StudyPulse Cloud AI".localized())
                    .font(.title2.weight(.semibold))
                Text("Sign in securely with the StudyPulse identity center. Email/password, email code, and GitHub are supported on the web page.".localized())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await signIn() }
                } label: {
                    HStack {
                        if isWorking { ProgressView().tint(.white) }
                        else { Image(systemName: "safari.fill") }
                        Text("Continue to secure login".localized())
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(isWorking)
            }
            .padding(28)
            .navigationTitle("Login".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized()) { dismiss() }
                }
            }
            .alert("Login failed".localized(), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK".localized(), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onReceive(NotificationCenter.default.publisher(for: .studyPulseAuthCallbackHandled)) { notification in
                guard notification.object is AuthTokenPair else { return }
                isWorking = false
                dismiss()
            }
        }
    }

    @MainActor
    private func signIn() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let pair = try await webAuth.authenticate()
            try await CloudAuthLoginCoordinator.login(pair: pair, container: container)
            dismiss()
        } catch WebAuthError.cancelled {
            // User cancellation is expected and does not need an error alert.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
