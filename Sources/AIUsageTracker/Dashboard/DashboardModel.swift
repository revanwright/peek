import AppKit

/// Everything the menu bar dropdown shows, in display-ready form.
/// The real data sources fill this in; `DashboardModel.sample` is clearly-labeled fake data
/// used only for design previews.
struct DashboardModel {
    var claude: ClaudeState
    /// nil hides the section (turned off in Settings, or not built yet).
    var sessions: [CodeSession]?
    var apps: [AppTime]?
    var updatedAt: Date?
    /// True when this is made-up preview data. The panel shows a "Sample data" badge.
    var isSample = false

    enum ClaudeState {
        case disabled
        case signedOut
        case loading
        case unavailable(String)
        /// `warning` is set when the latest refresh failed and older numbers are shown.
        case ready(ClaudeLimit, warning: String?)
    }

    struct ClaudeLimit {
        var plan: String?
        var session: Window
        var weekly: Window?

        struct Window {
            var percent: Double
            /// nil when the window hasn't started (no usage yet).
            var resetsAt: Date?
        }
    }

    struct CodeSession: Identifiable {
        enum Status {
            case working, needsPermission, waitingForReply, finished
        }

        var id: String
        var project: String
        var status: Status
        var since: Date
    }

    struct AppTime: Identifiable {
        var id: String { bundleID }
        var bundleID: String
        var name: String
        var icon: NSImage
        var seconds: TimeInterval
    }
}

// MARK: - Sample data (design previews only)

extension DashboardModel {
    static var sample: DashboardModel {
        let now = Date()
        return DashboardModel(
            claude: .ready(ClaudeLimit(
                plan: "Pro",
                session: .init(percent: 34, resetsAt: now.addingTimeInterval(2 * 3600 + 14 * 60)),
                weekly: .init(percent: 52, resetsAt: now.addingTimeInterval(3.8 * 24 * 3600))
            ), warning: nil),
            sessions: [
                CodeSession(id: "1", project: "Harvey", status: .needsPermission, since: now.addingTimeInterval(-40)),
                CodeSession(id: "2", project: "ai-usage-tracker", status: .working, since: now.addingTimeInterval(-180)),
                CodeSession(id: "3", project: "Campus Tag", status: .waitingForReply, since: now.addingTimeInterval(-6 * 60)),
                CodeSession(id: "4", project: "meeting-scribe", status: .finished, since: now.addingTimeInterval(-14 * 60)),
            ],
            apps: [
                AppTime(bundleID: "com.lencx.chatgpt", name: "ChatGPT", icon: appIcon("/Applications/ChatGPT.app"), seconds: 72 * 60),
                AppTime(bundleID: "com.meta.endo", name: "Muse", icon: appIcon("/Applications/Muse.app"), seconds: 24 * 60),
            ],
            updatedAt: now.addingTimeInterval(-60),
            isSample: true
        )
    }

    static func appIcon(_ path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }
}

// MARK: - Live data

extension DashboardModel {
    @MainActor
    static func live(usage: UsageStore) -> DashboardModel {
        DashboardModel(
            claude: claudeState(usage),
            sessions: nil,  // Claude Code sessions: next build step
            apps: nil,      // AI app time: later build step
            updatedAt: usage.snapshot?.fetchedAt
        )
    }

    @MainActor
    private static func claudeState(_ usage: UsageStore) -> ClaudeState {
        guard usage.isEnabled else { return .disabled }
        let warning: String? = if case .failed(let message) = usage.phase { message } else { nil }

        if let snapshot = usage.snapshot, let five = snapshot.fiveHour {
            let limit = ClaudeLimit(
                plan: usage.plan,
                session: .init(percent: five.utilization, resetsAt: five.resetsAt),
                weekly: snapshot.weekly.map { .init(percent: $0.utilization, resetsAt: $0.resetsAt) }
            )
            return .ready(limit, warning: warning)
        }
        switch usage.phase {
        case .needsSignIn: return .signedOut
        case .failed(let message): return .unavailable(message)
        case .loading, .ready: return .loading
        }
    }
}
