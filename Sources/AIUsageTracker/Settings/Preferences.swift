import Foundation

/// Names of the user's saved choices (stored in the app's standard preferences file).
enum PrefKey {
    static let openAtLogin = "openAtLogin"
    static let menuBarStyle = "menuBarStyle"
    static let refreshMinutes = "refreshMinutes"
    static let settingsTab = "settingsTab"

    static let trackClaudeLimit = "source.claudeLimit"
    static let trackClaudeCode = "source.claudeCode"
    static func trackApp(_ bundleID: String) -> String { "source.app.\(bundleID)" }

    static let warnEnabled = "alert.warnEnabled"
    static let warnAtPercent = "alert.warnAtPercent"
    static let notifyOnReset = "alert.notifyOnReset"
    static let sessionAlerts = "alert.sessions"
    static let sessionAlertPermission = "alert.sessions.permission"
    static let sessionAlertReply = "alert.sessions.reply"
    static let sessionAlertFinished = "alert.sessions.finished"
    /// The Claude app already notifies you about its own sessions, so these are off by default.
    static let sessionAlertClaudeApp = "alert.sessions.claudeApp"
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case ringOnly, ringAndPercent
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ringOnly: "Ring only"
        case .ringAndPercent: "Ring and percentage"
        }
    }

    static var current: MenuBarStyle {
        UserDefaults.standard.string(forKey: PrefKey.menuBarStyle).flatMap(MenuBarStyle.init) ?? .ringOnly
    }
}

enum AlertSettings {
    /// The usage level where colors turn red and the warning notification fires.
    static var warnAtPercent: Double {
        let saved = UserDefaults.standard.double(forKey: PrefKey.warnAtPercent)
        return saved == 0 ? 80 : saved
    }
}

/// An AI app whose time-in-front is tracked.
struct TrackedApp: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let name: String

    static let defaults: [TrackedApp] = [
        TrackedApp(bundleID: "com.lencx.chatgpt", name: "ChatGPT"),
        TrackedApp(bundleID: "com.meta.endo", name: "Muse"),
    ]
}

enum Preferences {
    /// Reads an on/off setting, treating "never set" as `defaultValue`.
    static func isOn(_ key: String, default defaultValue: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }
}
