import Foundation

enum GitHubError: LocalizedError {
    case badStatus(Int, String)
    case notFound
    case conflict
    case badCredentials

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, let message): return "GitHub error \(code): \(message)"
        case .notFound: return "Not found"
        case .conflict: return "Conflict — someone else updated the file"
        case .badCredentials: return "Invalid token. Check that your personal access token is correct and has the 'repo' scope."
        }
    }
}

struct GitHubUser: Codable {
    let login: String
}

struct RepoInfo: Codable {
    let name: String
    let defaultBranch: String

    enum CodingKeys: String, CodingKey {
        case name
        case defaultBranch = "default_branch"
    }
}

/// Metadata for a file as returned by the contents API.
struct ContentMeta: Codable {
    let path: String
    let sha: String
    let size: Int64
    let content: String?      // base64, only present for files <= 1 MB
    let encoding: String?
}

/// Thin async client for the GitHub REST API.
struct GitHubClient {
    let username: String
    let token: String

    private let base = URL(string: "https://api.github.com")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    private func request(_ method: String, _ path: String, accept: String = "application/vnd.github+json", body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(accept, forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    private func send(_ req: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200...299:
            return (data, code)
        case 401:
            throw GitHubError.badCredentials
        case 404:
            throw GitHubError.notFound
        case 409, 422 where (String(data: data, encoding: .utf8) ?? "").contains("sha"):
            throw GitHubError.conflict
        default:
            let message = String(data: data, encoding: .utf8) ?? ""
            throw GitHubError.badStatus(code, String(message.prefix(300)))
        }
    }

    // MARK: - Auth

    /// Returns the username a token belongs to (and validates it in the process).
    static func login(token: String) async throws -> String {
        let probe = GitHubClient(username: "", token: token)
        let (data, _) = try await probe.send(probe.request("GET", "user"))
        return try JSONDecoder().decode(GitHubUser.self, from: data).login
    }

    // MARK: - Repos

    func repoExists(_ name: String) async throws -> Bool {
        do {
            _ = try await send(request("GET", "repos/\(username)/\(name)"))
            return true
        } catch GitHubError.notFound {
            return false
        }
    }

    func createPrivateRepo(_ name: String, description: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "description": description,
            "private": true,
            "auto_init": true,
        ] as [String: Any])
        _ = try await send(request("POST", "user/repos", body: body))
    }

    // MARK: - Contents

    /// File metadata (sha, size). Content field is only populated for files <= 1 MB.
    func contentMeta(repo: String, path: String) async throws -> ContentMeta {
        let (data, _) = try await send(request("GET", "repos/\(username)/\(repo)/contents/\(path)"))
        return try JSONDecoder().decode(ContentMeta.self, from: data)
    }

    /// Raw bytes of a file (works for files up to 100 MB).
    func rawContent(repo: String, path: String) async throws -> Data {
        let (data, _) = try await send(request("GET", "repos/\(username)/\(repo)/contents/\(path)", accept: "application/vnd.github.raw+json"))
        return data
    }

    /// Creates or updates a file. Pass the current `sha` when updating. Returns the new blob sha.
    func putContent(repo: String, path: String, data: Data, message: String, sha: String? = nil) async throws -> String {
        var payload: [String: Any] = [
            "message": message,
            "content": data.base64EncodedString(),
        ]
        if let sha { payload["sha"] = sha }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (respData, _) = try await send(request("PUT", "repos/\(username)/\(repo)/contents/\(path)", body: body))
        struct PutResponse: Codable {
            struct C: Codable { let sha: String }
            let content: C
        }
        return try JSONDecoder().decode(PutResponse.self, from: respData).content.sha
    }

    func deleteContent(repo: String, path: String, sha: String, message: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "message": message,
            "sha": sha,
        ])
        _ = try await send(request("DELETE", "repos/\(username)/\(repo)/contents/\(path)", body: body))
    }
}
