import SwiftUI
import Observation

@MainActor
@Observable
final class AppState {
    var store: PhotoStore?

    var isSignedIn: Bool { store != nil }

    init() {
        if let username = Keychain.load("username"), let token = Keychain.load("token") {
            store = PhotoStore(client: GitHubClient(username: username, token: token))
        }
    }

    /// Validates the token against the GitHub API (which also tells us the
    /// username), then persists both. Works for OAuth and manual tokens alike.
    func signIn(token: String) async throws {
        let username = try await GitHubClient.login(token: token)
        Keychain.save(username, for: "username")
        Keychain.save(token, for: "token")
        store = PhotoStore(client: GitHubClient(username: username, token: token))
    }

    func signOut() {
        Keychain.delete("username")
        Keychain.delete("token")
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
                LibraryView(store: store)
                    .environment(appState)
                    .id(store.client.username)
            } else {
                SignInView()
                    .environment(appState)
            }
        }
    }
}
