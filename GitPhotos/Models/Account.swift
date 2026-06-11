import Foundation

/// A signed-in GitHub account. The first one (primary) holds the index repo;
/// the rest are extra storage accounts photos can be spread across.
struct Account: Codable, Hashable, Identifiable {
    let login: String
    let token: String
    var id: String { login }
}

extension Keychain {
    private static let accountsKey = "accounts"

    static func saveAccounts(_ accounts: [Account]) {
        if let data = try? JSONEncoder().encode(accounts) {
            save(String(decoding: data, as: UTF8.self), for: accountsKey)
        }
    }

    static func loadAccounts() -> [Account] {
        if let json = load(accountsKey),
           let data = json.data(using: .utf8),
           let accounts = try? JSONDecoder().decode([Account].self, from: data),
           !accounts.isEmpty {
            return accounts
        }
        // Migrate the old single-account format.
        if let login = load("username"), let token = load("token") {
            let migrated = [Account(login: login, token: token)]
            saveAccounts(migrated)
            return migrated
        }
        return []
    }

    static func clearAccounts() {
        delete(accountsKey)
        delete("username")
        delete("token")
    }
}
