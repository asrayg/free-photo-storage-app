import Foundation

enum Config {
    /// OAuth client ID for "Sign in with GitHub" (device flow).
    ///
    /// One-time setup: register an OAuth app at
    /// https://github.com/settings/applications/new
    /// (any homepage/callback URL works, e.g. http://127.0.0.1),
    /// check "Enable Device Flow", then paste the Client ID here.
    /// No client secret is needed — the device flow doesn't use one.
    ///
    /// While this is empty, the sign-in screen falls back to manual
    /// personal-access-token entry.
    static let githubClientID = ""
}
