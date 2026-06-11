import SwiftUI
import Observation

@MainActor
@Observable
final class AppState {
    var store: PhotoStore?

    var isSignedIn: Bool { store != nil }

    init() {
        let accounts = Keychain.loadAccounts()
        if !accounts.isEmpty {
            store = PhotoStore(accounts: accounts)
        }
    }

    /// Validates the token against the GitHub API (which also tells us the
    /// username), then persists it. Works for OAuth and manual tokens alike.
    func signIn(token: String) async throws {
        let login = try await GitHubClient.login(token: token)
        let accounts = [Account(login: login, token: token)]
        Keychain.saveAccounts(accounts)
        store = PhotoStore(accounts: accounts)
    }

    func signOut() {
        Keychain.clearAccounts()
        store = nil
        Task { await ImageCache.shared.clearAll() }
    }
}

@main
@MainActor
struct GitPhotosApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            if let store = appState.store {
                RootView(store: store)
                    .environment(appState)
                    .id(store.primary.login)
            } else {
                SignInView()
                    .environment(appState)
            }
        }
    }
}
