import Foundation

/// GitHub OAuth device flow (RFC 8628): the app shows a short code, the user
/// enters it at github.com/login/device, and we poll until GitHub hands us a
/// token. Needs only a public client ID — no secret, so it's safe in an app.
struct GitHubDeviceFlow {
    let clientID: String

    struct DeviceCode {
        let deviceCode: String
        let userCode: String          // what the user types, e.g. "WDJB-MJHT"
        let verificationURL: URL      // https://github.com/login/device
        let expiresIn: TimeInterval
        let pollInterval: TimeInterval
    }

    enum FlowError: LocalizedError {
        case denied
        case expired
        case server(String)

        var errorDescription: String? {
            switch self {
            case .denied: return "Sign-in was cancelled on GitHub."
            case .expired: return "The code expired. Try signing in again."
            case .server(let message): return "GitHub error: \(message)"
            }
        }
    }

    private func post(_ url: URL, params: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FlowError.server("unexpected response")
        }
        return json
    }

    func requestCode() async throws -> DeviceCode {
        let json = try await post(
            URL(string: "https://github.com/login/device/code")!,
            params: ["client_id": clientID, "scope": "repo"])
        guard let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String,
              let uri = json["verification_uri"] as? String,
              let url = URL(string: uri) else {
            let message = (json["error_description"] as? String) ?? (json["error"] as? String) ?? "unexpected response"
            throw FlowError.server(message)
        }
        return DeviceCode(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURL: url,
            expiresIn: (json["expires_in"] as? TimeInterval) ?? 900,
            pollInterval: (json["interval"] as? TimeInterval) ?? 5)
    }

    /// Polls until the user approves on github.com. Cancellable via task cancellation.
    func waitForToken(_ code: DeviceCode) async throws -> String {
        var interval = max(code.pollInterval, 5)
        let deadline = ContinuousClock.now + .seconds(code.expiresIn)

        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .seconds(interval))
            let json = try await post(
                URL(string: "https://github.com/login/oauth/access_token")!,
                params: [
                    "client_id": clientID,
                    "device_code": code.deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                ])
            if let token = json["access_token"] as? String {
                return token
            }
            switch json["error"] as? String {
            case "authorization_pending":
                continue
            case "slow_down":
                interval += 5
            case "access_denied":
                throw FlowError.denied
            case "expired_token":
                throw FlowError.expired
            default:
                throw FlowError.server((json["error_description"] as? String) ?? "unknown error")
            }
        }
        throw FlowError.expired
    }
}
