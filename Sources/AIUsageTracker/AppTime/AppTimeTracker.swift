import AppKit
import CoreGraphics
import Observation

/// Measures time spent in your tracked AI apps today.
///
/// Every 5 seconds it checks which app is in front, whether the screen is locked,
/// and how long since you last used the keyboard or mouse, and hands that to
/// `AppTimeLedger`, which does the counting. None of this needs a special macOS
/// permission. Totals are saved, so they survive restarts.
@Observable
@MainActor
final class AppTimeTracker {
    /// Seconds per app (bundle ID) so far today.
    private(set) var today: [String: Double] = [:]

    private var ledger: AppTimeLedger
    private var screenLocked = false
    private var tickTask: Task<Void, Never>?
    private var ticksSinceSave = 0

    private static let storageKey = "appTime.ledger"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(AppTimeLedger.self, from: data) {
            ledger = saved
        } else {
            ledger = AppTimeLedger()
        }
        today = ledger.seconds(on: .now)
        guard !DesignPreview.isEnabled else { return }

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLocked = true }
        }
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLocked = false }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func tick() {
        let tracked = Set(TrackedApps.shared.apps
            .map(\.bundleID)
            .filter { Preferences.isOn(PrefKey.trackApp($0)) })
        // Seconds since any keyboard, mouse, or trackpad input. Needs no permission.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)

        ledger.tick(
            now: .now,
            frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            tracked: tracked,
            idleSeconds: idle,
            screenLocked: screenLocked
        )

        let updated = ledger.seconds(on: .now)
        if updated != today { today = updated }

        ticksSinceSave += 1
        if ticksSinceSave >= 12 { save() }  // about once a minute
    }

    private func save() {
        ticksSinceSave = 0
        ledger.prune(keeping: 7)
        if let data = try? JSONEncoder().encode(ledger) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
