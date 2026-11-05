import AppKit
import Observation

/// Keeps the latest Claude limit reading and refreshes it on a schedule.
@Observable
@MainActor
final class UsageStore {
    enum Phase: Equatable {
        case needsSignIn
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var snapshot: UsageSnapshot?
    private(set) var plan: String?
    private(set) var isRefreshing = false

    /// Opening the menu refreshes, but never more often than this.
    private let minimumGap: TimeInterval = 60

    private let client = ClaudeUsageClient()
    private var pollTask: Task<Void, Never>?
    private var signInWindow: SignInWindowController?

    var isEnabled: Bool { Preferences.isOn(PrefKey.trackClaudeLimit) }

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Give Wi-Fi a moment to reconnect after waking.
                try? await Task.sleep(for: .seconds(10))
                await self?.refresh(force: true)
            }
        }
        Task { await start() }
    }

    private func start() async {
        // Sample-data previews never touch your real account.
        guard !DesignPreview.isEnabled else { return }

        // Read Keychain off the main thread: if macOS shows an "allow access?" prompt,
        // the menu bar stays responsive while it waits for you.
        let savedKey = await Task.detached { Keychain.read(.claudeSessionKey) }.value
        if let key = savedKey {
            await ClaudeWebSession.shared.installSessionKey(key)
            await refresh(force: true)
        } else {
            phase = .needsSignIn
        }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let minutes = max(UserDefaults.standard.integer(forKey: PrefKey.refreshMinutes), 0)
                try? await Task.sleep(for: .seconds(60 * (minutes == 0 ? 5 : minutes)))
                await self?.refresh(force: true)
            }
        }
    }

    /// - Parameter force: Skip the "checked less than a minute ago" shortcut.
    func refresh(force: Bool = false) async {
        guard isEnabled, phase != .needsSignIn, !isRefreshing else { return }
        if !force, let last = snapshot?.fetchedAt, Date().timeIntervalSince(last) < minimumGap { return }

        isRefreshing = true
        defer { isRefreshing = false }
        if snapshot == nil { phase = .loading }

        do {
            let result = try await client.fetch()
            snapshot = result.snapshot
            plan = result.plan
            phase = .ready
            Notifier.shared.usageUpdated(result.snapshot)
        } catch ClaudeUsageClient.FetchError.signedOut {
            snapshot = nil
            phase = .needsSignIn
        } catch {
            Log.write("refresh failed: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// Recent chats and whether each is still being answered. nil when not signed in
    /// or claude.ai couldn't be reached (the chat section then just stays as it was).
    func chatActivity(recentWithin: TimeInterval) async -> [ClaudeUsageClient.ChatActivity]? {
        // Wait until the limit reader has loaded claude.ai, so the two never load it at once.
        guard phase == .ready || snapshot != nil, !isRefreshing else { return nil }
        do {
            return try await client.fetchChatActivity(recentWithin: recentWithin)
        } catch {
            Log.write("chats: couldn't check (\(error.localizedDescription))")
            return nil
        }
    }

    func signIn() {
        if let signInWindow {
            signInWindow.show()
            return
        }
        let controller = SignInWindowController(
            onSignedIn: { [weak self] key in
                Task.detached { Keychain.save(key, for: .claudeSessionKey) }
                guard let self else { return }
                client.reset()
                phase = .loading
                Task { await self.refresh(force: true) }
            },
            onClose: { [weak self] in self?.signInWindow = nil }
        )
        signInWindow = controller
        controller.show()
    }

    func signOut() {
        Task.detached { Keychain.delete(.claudeSessionKey) }
        client.reset()
        snapshot = nil
        plan = nil
        phase = .needsSignIn
        Task { await ClaudeWebSession.shared.clear() }
        Log.write("signed out")
    }
}
