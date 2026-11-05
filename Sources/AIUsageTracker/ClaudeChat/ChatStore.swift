import AppKit
import CoreGraphics
import Observation

/// Shows when a regular Claude chat is replying.
///
/// Chats have no hooks like Claude Code does, so this asks claude.ai directly, through
/// the same signed-in hidden browser that reads your limit. claude.ai saves Claude's
/// reply only when it's finished, so a recent chat whose newest message is yours is
/// still being answered. That covers chats in the Claude app, on the web, and on your phone.
///
/// It checks more often while it matters (a reply in progress, or the Claude app in front)
/// and rarely when you're away, to keep requests to claude.ai light.
@Observable
@MainActor
final class ChatStore {
    struct Chat: Identifiable, Equatable {
        let id: String
        let name: String
        let isReplying: Bool
        /// When the reply started (while replying) or finished.
        let since: Date
    }

    private(set) var chats: [Chat] = []

    var isEnabled: Bool { Preferences.isOn(PrefKey.trackClaudeChat) }

    nonisolated static let claudeAppID = "com.anthropic.claudefordesktop"
    /// How long a finished chat stays listed.
    private let showFor: TimeInterval = 10 * 60
    /// Longest a reply is assumed to take (research can run long). A message still
    /// unanswered after this most likely failed, so it stops showing as Working.
    private let longestReply: TimeInterval = 30 * 60

    private let usage: UsageStore
    private var replyStarted: [String: Date] = [:]
    private var replyFinished: [String: Date] = [:]
    private var lastCheck = Date.distantPast
    private var checkSoon = false
    private var lastRecentCount = -1
    private var lastDebug: [String: String] = [:]
    private var loop: Task<Void, Never>?

    init(usage: UsageStore) {
        self.usage = usage
        guard !DesignPreview.isEnabled else { return }

        // Switching to the Claude app usually means a chat is about to start.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Self.claudeAppID else { return }
            MainActor.assumeIsolated { self?.checkSoon = true }
        }

        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self else { return }
                if checkSoon || Date().timeIntervalSince(lastCheck) >= nextDelay() {
                    await check()
                }
            }
        }
    }

    /// Asks for a check on the next tick (used when the menu opens).
    func refreshSoon() { checkSoon = true }

    private func check() async {
        checkSoon = false
        lastCheck = .now
        guard isEnabled else {
            if !chats.isEmpty { chats = [] }
            return
        }
        guard let activity = await usage.chatActivity(recentWithin: longestReply) else {
            // Not ready yet (still reading the limit) or claude.ai was unreachable: try again in 15 seconds.
            lastCheck = Date().addingTimeInterval(15 - nextDelay())
            return
        }
        lastCheck = .now
        if activity.count != lastRecentCount {
            lastRecentCount = activity.count
            Log.write("chats: checked, \(activity.count) chat(s) active in the last 30 minutes")
        }

        let now = Date()
        var next: [Chat] = []
        for chat in activity {
            if lastDebug[chat.id] != chat.debug {
                lastDebug[chat.id] = chat.debug
                Log.write("chats: \(chat.id.prefix(8)) \(chat.debug)")
            }
            let sent = chat.lastMessageAt ?? chat.updatedAt
            if chat.isReplying, now.timeIntervalSince(sent) < longestReply {
                let started = replyStarted[chat.id] ?? sent
                if replyStarted[chat.id] == nil { Log.write("chats: a reply started") }
                replyStarted[chat.id] = started
                replyFinished[chat.id] = nil
                next.append(Chat(id: chat.id, name: chat.name, isReplying: true, since: started))
            } else {
                if replyStarted.removeValue(forKey: chat.id) != nil {
                    replyFinished[chat.id] = now
                    Log.write("chats: a reply finished")
                    Notifier.shared.chatFinished(id: chat.id, name: chat.name)
                }
                let finished = max(chat.updatedAt, replyFinished[chat.id] ?? .distantPast)
                guard !chat.isReplying, now.timeIntervalSince(finished) < showFor else { continue }
                next.append(Chat(id: chat.id, name: chat.name, isReplying: false, since: finished))
            }
        }
        // Forget chats that dropped out of the recent list.
        let ids = Set(activity.map(\.id))
        replyStarted = replyStarted.filter { ids.contains($0.key) }
        replyFinished = replyFinished.filter { ids.contains($0.key) }

        if next != chats { chats = next }
    }

    /// Seconds between checks.
    private func nextDelay() -> TimeInterval {
        if chats.contains(where: \.isReplying) { return 8 }  // catch the finish quickly
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.claudeAppID { return 15 }
        if !chats.isEmpty { return 20 }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        return idle > 300 ? 180 : 45
    }

    /// Opens a chat in the Claude app, or on claude.ai if the app isn't installed.
    static func open(chatID: String) {
        let workspace = NSWorkspace.shared
        let hasApp = workspace.urlForApplication(withBundleIdentifier: claudeAppID) != nil
        let address = hasApp ? "claude://claude.ai/chat/\(chatID)" : "https://claude.ai/chat/\(chatID)"
        guard let url = URL(string: address) else { return }
        let opened = workspace.open(url)
        Log.write("chats: opened \(hasApp ? "claude://" : "https://") link for \(chatID.prefix(8)) → \(opened ? "ok" : "failed")")
    }
}
