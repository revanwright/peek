import Foundation
import WebKit

/// The one "browser profile" the app uses to talk to claude.ai.
///
/// Cookies are kept in memory only. The single thing that survives a restart is
/// the session key, and that lives in Keychain (see `Keychain`), not on disk.
/// Both the sign-in window and the background usage reader share this profile,
/// so signing in once is enough for both.
@MainActor
final class ClaudeWebSession {
    static let shared = ClaudeWebSession()

    let dataStore = WKWebsiteDataStore.nonPersistent()

    /// Makes the built-in web engine identify itself like regular Safari.
    private static let userAgentSuffix = "Version/26.0 Safari/605.1.15"

    func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.applicationNameForUserAgent = Self.userAgentSuffix
        return configuration
    }

    /// Restores a saved session key into the in-memory profile (after an app restart).
    func installSessionKey(_ key: String) async {
        let properties: [HTTPCookiePropertyKey: Any] = [
            .domain: ".claude.ai",
            .path: "/",
            .name: "sessionKey",
            .value: key,
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(60 * 60 * 24 * 30),
        ]
        guard let cookie = HTTPCookie(properties: properties) else { return }
        await dataStore.httpCookieStore.setCookie(cookie)
    }

    func cookieValue(named name: String) async -> String? {
        let cookies = await dataStore.httpCookieStore.allCookies()
        return cookies.first { $0.name == name && $0.domain.hasSuffix("claude.ai") }?.value
    }

    /// Forgets everything claude.ai stored (used for sign-out and fresh sign-ins).
    func clear() async {
        await dataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
    }
}
