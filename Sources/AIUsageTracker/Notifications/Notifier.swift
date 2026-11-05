import AppKit
import Observation
@preconcurrency import UserNotifications

/// Sends the app's notifications:
///   - a warning when Claude usage reaches your warning level (once per limit window),
///   - a ping when a limit you'd pushed close to the edge resets,
///   - a nudge when a Claude Code session needs you,
///   - (optional) a ping when a chat reply finishes.
@Observable
@MainActor
final class Notifier: NSObject {
    static let shared = Notifier()

    enum Permission { case unknown, allowed, denied }
    private(set) var permission: Permission = .unknown

    /// Called when you click a session notification (opens that session's window).
    var openSession: ((String) -> Void)?

    private let center = UNUserNotificationCenter.current()
    /// Waits before nudging about a session, so you aren't pinged for something
    /// you're already looking at and answer right away.
    private let sessionGracePeriod: Duration = .seconds(8)
    private var pendingSessionNudges: [String: Task<Void, Never>] = [:]

    private override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Permission

    func requestPermissionIfNeeded() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            permission = granted ? .allowed : .denied
            Log.write("notifications: permission \(granted ? "granted" : "declined")")
        case .denied:
            permission = .denied
        default:
            permission = .allowed
        }
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Claude limit

    func usageUpdated(_ snapshot: UsageSnapshot) {
        let warnAt = AlertSettings.warnAtPercent
        let windows: [(UsageWindow?, String)] = [(snapshot.fiveHour, "5-hour"), (snapshot.weekly, "weekly")]

        for case let (window?, name) in windows {
            guard window.utilization >= warnAt, let resetsAt = window.resetsAt else { continue }

            // One warning per limit window: remember which window we already warned about.
            let key = "notified.warning.\(window.key)"
            let windowID = String(Int(resetsAt.timeIntervalSince1970))
            guard UserDefaults.standard.string(forKey: key) != windowID else { continue }
            UserDefaults.standard.set(windowID, forKey: key)

            if Preferences.isOn(PrefKey.warnEnabled) {
                let percent = Int(window.utilization.rounded())
                let when = window.key == "five_hour"
                    ? "in \(Countdown.short(to: resetsAt))"
                    : resetsAt.formatted(.dateTime.weekday(.wide).hour().minute())
                send(
                    id: "warning-\(window.key)-\(windowID)",
                    title: "Claude usage at \(percent)%",
                    body: "You've used \(percent)% of your \(name) limit. It resets \(when)."
                )
            }
            if Preferences.isOn(PrefKey.notifyOnReset) {
                scheduleResetPing(windowName: name, key: window.key, at: resetsAt)
            }
        }
    }

    /// Scheduled with macOS directly, so it arrives on time even if the app is busy.
    private func scheduleResetPing(windowName: String, key: String, at date: Date) {
        let delay = date.timeIntervalSinceNow + 30  // a little after, so the new window is really open
        guard delay > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your Claude limit has reset"
        content.body = key == "five_hour"
            ? "You have a fresh 5-hour window."
            : "Your weekly limit is back to 0%."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        center.add(UNNotificationRequest(identifier: "reset-\(key)-\(Int(date.timeIntervalSince1970))", content: content, trigger: trigger))
        Log.write("notifications: reset ping scheduled for \(key) at \(date.formatted(.iso8601))")
    }

    // MARK: - Claude Code sessions

    func sessionChanged(_ session: ClaudeCodeStore.Session) {
        pendingSessionNudges[session.id]?.cancel()
        pendingSessionNudges[session.id] = nil

        guard Preferences.isOn(PrefKey.sessionAlerts), let message = nudge(for: session) else { return }
        if session.isInClaudeApp, !Preferences.isOn(PrefKey.sessionAlertClaudeApp, default: false) { return }

        pendingSessionNudges[session.id] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: sessionGracePeriod)
            guard !Task.isCancelled else { return }
            pendingSessionNudges[session.id] = nil
            send(
                id: "session-\(session.id)",
                title: message.title,
                body: message.body,
                userInfo: ["sessionID": session.id]
            )
        }
    }

    private func nudge(for session: ClaudeCodeStore.Session) -> (title: String, body: String)? {
        let client = session.clientName.map { " in \($0)" } ?? ""
        switch session.status {
        case .needsPermission where Preferences.isOn(PrefKey.sessionAlertPermission):
            return ("\(session.name) needs permission", "Claude Code is waiting for you to approve an action\(client).")
        case .waitingForReply where Preferences.isOn(PrefKey.sessionAlertReply):
            return ("\(session.name) is waiting for your reply", "Claude Code asked you a question\(client).")
        case .finished where Preferences.isOn(PrefKey.sessionAlertFinished, default: false):
            return ("\(session.name) finished", "Claude Code is done and ready for your next message\(client).")
        default:
            return nil
        }
    }

    // MARK: - Claude chat

    func chatFinished(id: String, name: String) {
        guard Preferences.isOn(PrefKey.chatAlertFinished, default: false) else { return }
        send(
            id: "chat-\(id)-\(Int(Date().timeIntervalSince1970))",
            title: "Claude replied",
            body: name.isEmpty ? "Your chat has a new reply." : "“\(name)” has a new reply.",
            userInfo: ["chatID": id]
        )
    }

    // MARK: - Sending

    func sendTest() {
        send(id: "test-\(UUID().uuidString)", title: "Notifications are working", body: "This is how Peek will let you know about your Claude usage.")
    }

    private func send(id: String, title: String, body: String, userInfo: [String: String] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
            if let error { Log.write("notifications: couldn't send: \(error.localizedDescription)") }
        }
        Log.write("notifications: sent \"\(title)\"")
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    /// Show banners even though the app counts as "active" (menu bar apps always are).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        if let chatID = info["chatID"] as? String {
            await MainActor.run { ChatStore.open(chatID: chatID) }
        }
        guard let sessionID = info["sessionID"] as? String else { return }
        await MainActor.run { self.openSession?(sessionID) }
    }
}
