import SwiftUI

@main
struct AIUsageTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var usage: UsageStore
    @State private var claudeCode = ClaudeCodeStore()
    @State private var appTime = AppTimeTracker()
    @State private var chat: ChatStore

    // Read here so the menu bar redraws as soon as these settings change.
    @AppStorage(PrefKey.menuBarStyle) private var menuBarStyle = MenuBarStyle.ringOnly.rawValue
    @AppStorage(PrefKey.warnAtPercent) private var warnAtPercent = 80.0
    @AppStorage(PrefKey.trackClaudeLimit) private var trackClaudeLimit = true

    init() {
        let usage = UsageStore()
        _usage = State(initialValue: usage)
        _chat = State(initialValue: ChatStore(usage: usage))
    }

    var body: some Scene {
        MenuBarExtra {
            if DesignPreview.isEnabled {
                UsagePanel(model: .sample)
            } else {
                UsagePanel(
                    model: .live(usage: usage, claudeCode: claudeCode, appTime: appTime, chat: chat),
                    onSignIn: { usage.signIn() },
                    onRetry: { Task { await usage.refresh(force: true) } },
                    onOpen: {
                        claudeCode.reload()
                        chat.refreshSoon()
                        Task { await usage.refresh() }
                    },
                    onOpenSession: { session in
                        if let match = claudeCode.sessions.first(where: { $0.id == session.id }) {
                            claudeCode.open(match)
                        }
                    },
                    onOpenChat: { chat in ChatStore.open(chatID: chat.id) }
                )
            }
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(account: accountInfo, hooks: hookControls)
                .previewActiveControls()
        }
    }

    private var menuBarLabel: some View {
        let percent: Double? = if DesignPreview.isEnabled {
            34
        } else if trackClaudeLimit {
            usage.snapshot?.fiveHour?.utilization
        } else {
            nil
        }
        _ = warnAtPercent  // ring color depends on the warning level
        return Image(nsImage: MenuBarIcon.image(
            percent: percent,
            showsPercent: MenuBarStyle(rawValue: menuBarStyle) == .ringAndPercent
        ))
    }

    private var hookControls: HookControls {
        if DesignPreview.isEnabled {
            return HookControls(status: .installed, install: {}, remove: {})
        }
        return HookControls(
            status: claudeCode.hookStatus,
            install: { Task { await claudeCode.installHooks() } },
            remove: { Task { await claudeCode.removeHooks() } }
        )
    }

    private var accountInfo: AccountInfo {
        if DesignPreview.isEnabled {
            return AccountInfo(isSignedIn: true, plan: "Pro", lastChecked: .now.addingTimeInterval(-60), signIn: {}, signOut: {})
        }
        return AccountInfo(
            isSignedIn: usage.phase != .needsSignIn,
            plan: usage.plan,
            lastChecked: usage.snapshot?.fetchedAt,
            signIn: { usage.signIn() },
            signOut: { usage.signOut() }
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("launched args=\(CommandLine.arguments.dropFirst().joined(separator: " "))")
        guard DesignPreview.isEnabled else {
            Task { await Notifier.shared.requestPermissionIfNeeded() }
            return
        }
        if let appearance = DesignPreview.appearance {
            NSApp.appearance = NSAppearance(named: appearance)
        }
        // Behave like a regular app (Dock icon, normal windows) so screenshot tools can see it.
        NSApp.setActivationPolicy(.regular)
        previewWindow = DesignPreview.makeDropdownWindow()
        previewWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            DesignPreview.openSettings()
        }
        if let folder = DesignPreview.snapshotFolder, let previewWindow {
            Task { await DesignPreview.saveSnapshots(dropdown: previewWindow, to: folder) }
        }
    }
}
