import SwiftUI

@MainActor
struct SignInView: View {
    private enum Phase {
        case idle
        case requestingCode
        case waitingForApproval(GitHubDeviceFlow.DeviceCode)
    }

    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    @State private var phase = Phase.idle
    @State private var flowTask: Task<Void, Never>?
    @State private var manualToken = ""
    @State private var showManualEntry = Config.githubClientID.isEmpty
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showTokenHelp = false

    private var oauthAvailable: Bool { !Config.githubClientID.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                header

                if oauthAvailable {
                    oauthSection
                }

                if showManualEntry {
                    manualSection
                } else {
                    Section {
                        Button("Use a personal access token instead") {
                            showManualEntry = true
                        }
                        .font(.footnote)
                    }
                    .listRowBackground(Color.clear)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .sheet(isPresented: $showTokenHelp) {
            TokenHelpView()
        }
        .onDisappear { flowTask?.cancel() }
    }

    private var header: some View {
        Section {
            VStack(spacing: 12) {
                Text("GitPhotos")
                    .font(.largeTitle.bold())
                Text("Your photo library, stored for free in private GitHub repos. Storage shards are created automatically as your library grows.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var oauthSection: some View {
        switch phase {
        case .idle:
            Section {
                Button {
                    startDeviceFlow()
                } label: {
                    Label("Sign in with GitHub", systemImage: "person.badge.key")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            } footer: {
                Text("Opens GitHub in your browser — no token copying needed.")
            }

        case .requestingCode:
            Section {
                ProgressView("Contacting GitHub…")
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

        case .waitingForApproval(let code):
            Section {
                VStack(spacing: 16) {
                    Text("Enter this code on GitHub:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(code.userCode)
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = code.userCode
                        openURL(code.verificationURL)
                    } label: {
                        Label("Copy code & open GitHub", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Waiting for approval…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button("Cancel", role: .cancel) {
                        flowTask?.cancel()
                        phase = .idle
                    }
                    .font(.footnote)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
        }
    }

    private var manualSection: some View {
        Section {
            SecureField("ghp_…", text: $manualToken)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button {
                signIn(token: manualToken.trimmingCharacters(in: .whitespacesAndNewlines))
            } label: {
                if isWorking {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Sign in with token").frame(maxWidth: .infinity)
                }
            }
            .disabled(manualToken.isEmpty || isWorking)
        } header: {
            HStack {
                Text("Personal access token")
                Spacer()
                Button {
                    showTokenHelp = true
                } label: {
                    Label("How to get a token", systemImage: "info.circle")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .textCase(nil)
                }
            }
        } footer: {
            Button {
                showTokenHelp = true
            } label: {
                Text("Don't have a token? Tap ⓘ above for step-by-step instructions.")
                    .font(.footnote)
            }
        }
    }

    private func startDeviceFlow() {
        errorMessage = nil
        phase = .requestingCode
        let flow = GitHubDeviceFlow(clientID: Config.githubClientID)
        flowTask = Task {
            do {
                let code = try await flow.requestCode()
                phase = .waitingForApproval(code)
                let token = try await flow.waitForToken(code)
                try await appState.signIn(token: token)
            } catch is CancellationError {
                // user tapped Cancel
            } catch {
                errorMessage = error.localizedDescription
                phase = .idle
            }
        }
    }

    private func signIn(token: String) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await appState.signIn(token: token)
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
