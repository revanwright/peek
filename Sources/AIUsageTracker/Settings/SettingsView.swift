import SwiftUI

/// The Settings window (⌘, or the gear in the dropdown).
struct SettingsView: View {
    let account: AccountInfo
    let hooks: HookControls
    /// Remembers the last tab you looked at, like most Mac apps.
    @AppStorage(PrefKey.settingsTab) private var selectedTab = SettingsTab.general.rawValue

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general.rawValue)
            SourcesTab(hooks: hooks)
                .tabItem { Label("Sources", systemImage: "square.stack.3d.up") }
                .tag(SettingsTab.sources.rawValue)
            NotificationsTab()
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
                .tag(SettingsTab.notifications.rawValue)
            AccountTab(account: account)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(SettingsTab.account.rawValue)
        }
        .frame(width: 500)
    }
}

enum SettingsTab: String, CaseIterable {
    case general, sources, notifications, account
}

/// Connects the Sources tab to the Claude Code hook installer.
struct HookControls {
    var status: ClaudeCodeStore.HookStatus
    var install: () -> Void
    var remove: () -> Void
}

/// What the Account tab needs to know about the claude.ai sign-in.
struct AccountInfo {
    var isSignedIn: Bool
    var plan: String?
    var lastChecked: Date?
    var signIn: () -> Void
    var signOut: () -> Void
}

// MARK: - General

private struct GeneralTab: View {
    @AppStorage(PrefKey.openAtLogin) private var openAtLogin = false
    @AppStorage(PrefKey.menuBarStyle) private var menuBarStyle = MenuBarStyle.ringOnly.rawValue
    @AppStorage(PrefKey.refreshMinutes) private var refreshMinutes = 5

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, isOn in LoginItem.setEnabled(isOn) }
                Picker("Menu bar shows", selection: $menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }
            Section {
                Picker("Check Claude usage", selection: $refreshMinutes) {
                    Text("Every 2 minutes").tag(2)
                    Text("Every 5 minutes").tag(5)
                    Text("Every 10 minutes").tag(10)
                    Text("Every 15 minutes").tag(15)
                }
            } footer: {
                Text("Checking less often is gentler on claude.ai. Usage also refreshes when your Mac wakes and when you open the menu.")
                    .settingsFootnote()
            }

            Section {
                AboutRow()
            }
        }
        .formStyle(.grouped)
        .frame(height: 320)
        .onAppear { openAtLogin = LoginItem.isEnabled }
    }
}

/// App icon, name, and version.
private struct AboutRow: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Usage Tracker").font(.headline)
                Text(version).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Sources

private struct SourcesTab: View {
    let hooks: HookControls
    private var trackedApps: TrackedApps { TrackedApps.shared }
    @AppStorage(PrefKey.trackClaudeLimit) private var trackLimit = true
    @AppStorage(PrefKey.trackClaudeCode) private var trackCode = true
    @AppStorage(PrefKey.trackClaudeChat) private var trackChat = true
    @State private var confirmingInstall = false

    var body: some View {
        Form {
            Section("Claude") {
                SourceRow(
                    icon: .symbol("gauge.with.dots.needle.50percent", .orange),
                    title: "Plan limit",
                    subtitle: "5-hour and weekly usage from claude.ai",
                    isOn: $trackLimit
                )
                SourceRow(
                    icon: .symbol("terminal.fill", .indigo),
                    title: "Claude Code sessions",
                    subtitle: "Live status from Claude Code hooks",
                    isOn: $trackCode
                )
                HookStatusRow(hooks: hooks, confirmingInstall: $confirmingInstall)
                SourceRow(
                    icon: .symbol("bubble.left.and.bubble.right.fill", .teal),
                    title: "Claude chat",
                    subtitle: "Shows when a chat is replying, from claude.ai",
                    isOn: $trackChat
                )
            }

            Section {
                if trackedApps.apps.isEmpty {
                    Text("No apps yet. Add the AI apps you use.")
                        .foregroundStyle(.secondary)
                }
                ForEach(trackedApps.apps) { app in
                    AppSourceRow(app: app)
                        .contextMenu {
                            Button("Remove \(app.name)", role: .destructive) {
                                withAnimation { trackedApps.remove(app) }
                            }
                        }
                }
            } header: {
                Text("AI apps")
            } footer: {
                HStack(alignment: .top) {
                    Text("Time counts while the app is in front. Right-click an app to remove it.")
                        .settingsFootnote()
                    Spacer()
                    Button("Add App…") { trackedApps.chooseAndAdd() }
                        .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 460)
        .alert("Connect to Claude Code?", isPresented: $confirmingInstall) {
            Button("Connect", action: hooks.install)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This adds AI Usage Tracker's hooks to ~/.claude/settings.json so Claude Code can report each session's status. A backup of the file is saved first, and your other settings aren't changed.")
        }
    }
}

/// Shows whether Claude Code is set up to report to the app, with a button to fix it.
private struct HookStatusRow: View {
    let hooks: HookControls
    @Binding var confirmingInstall: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            Text(label).font(.callout).foregroundStyle(.secondary)
            Spacer()
            switch hooks.status {
            case .installed:
                Button("Disconnect", action: hooks.remove).controlSize(.small)
            case .notInstalled, .outdated, .failed:
                Button(hooks.status == .outdated ? "Update…" : "Connect…") { confirmingInstall = true }
                    .controlSize(.small)
            case .unknown:
                ProgressView().controlSize(.small)
            }
        }
        .padding(.leading, 34)
    }

    private var label: String {
        switch hooks.status {
        case .installed: "Connected to Claude Code"
        case .notInstalled: "Not connected"
        case .outdated: "Connected to an older copy of the app"
        case .failed: "Couldn't check the connection"
        case .unknown: "Checking…"
        }
    }

    private var dotColor: Color {
        switch hooks.status {
        case .installed: .green
        case .outdated, .failed: .orange
        case .notInstalled, .unknown: .secondary
        }
    }
}

private struct AppSourceRow: View {
    let app: TrackedApp
    @AppStorage private var isOn: Bool

    init(app: TrackedApp) {
        self.app = app
        _isOn = AppStorage(wrappedValue: true, PrefKey.trackApp(app.bundleID))
    }

    var body: some View {
        SourceRow(icon: .app(app.bundleID), title: app.name, subtitle: nil, isOn: $isOn)
    }
}

private struct SourceRow: View {
    enum Icon {
        case symbol(String, Color)
        case app(String)
    }

    let icon: Icon
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                iconView
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var iconView: some View {
        switch icon {
        case .symbol(let name, let color):
            Image(systemName: name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient))
        case .app(let bundleID):
            AppIconView(bundleID: bundleID, fallbackSymbol: "app.dashed", size: 26)
        }
    }
}

// MARK: - Notifications

private struct NotificationsTab: View {
    @AppStorage(PrefKey.warnEnabled) private var warnEnabled = true
    @AppStorage(PrefKey.warnAtPercent) private var warnAt = 80.0
    @AppStorage(PrefKey.notifyOnReset) private var notifyOnReset = true
    @AppStorage(PrefKey.sessionAlerts) private var sessionAlerts = true
    @AppStorage(PrefKey.sessionAlertPermission) private var alertPermission = true
    @AppStorage(PrefKey.sessionAlertReply) private var alertReply = true
    @AppStorage(PrefKey.sessionAlertFinished) private var alertFinished = false
    @AppStorage(PrefKey.sessionAlertClaudeApp) private var alertClaudeApp = false
    @AppStorage(PrefKey.chatAlertFinished) private var alertChatFinished = false

    var body: some View {
        Form {
            Section {
                Toggle("Warn me when I'm close to my limit", isOn: $warnEnabled)
                LabeledContent("Warning level") {
                    HStack(spacing: 10) {
                        Slider(value: $warnAt, in: 50...95, step: 5)
                            .frame(width: 170)
                        Text("\(Int(warnAt))%")
                            .monospacedDigit()
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                Toggle("Notify me when my limit resets", isOn: $notifyOnReset)
            } header: {
                Text("Claude limit")
            } footer: {
                Text("Rings turn red at your warning level. Reset notifications are sent only for limits you've pushed past your warning level.")
                    .settingsFootnote()
            }

            Section {
                Toggle("Notify me when a session is waiting on me", isOn: $sessionAlerts)
                Group {
                    Toggle("Needs permission", isOn: $alertPermission)
                    Toggle("Waiting for my reply", isOn: $alertReply)
                    Toggle("Finished", isOn: $alertFinished)
                    Toggle("Include sessions in the Claude app", isOn: $alertClaudeApp)
                }
                .padding(.leading, 18)
                .disabled(!sessionAlerts)
            } header: {
                Text("Claude Code")
            } footer: {
                Text("Sent after a few seconds, so you aren't pinged for something you answer right away. The Claude app already notifies you about its own sessions, so those are skipped unless you include them.")
                    .settingsFootnote()
            }

            Section {
                Toggle("Notify me when a chat reply finishes", isOn: $alertChatFinished)
            } header: {
                Text("Claude chat")
            } footer: {
                Text("Handy for long replies. Off by default because the Claude app can notify you itself.")
                    .settingsFootnote()
            }

            Section {
                NotificationPermissionRow()
            }
        }
        .formStyle(.grouped)
        .frame(height: 680)
        .animation(.smooth, value: sessionAlerts)
    }
}

/// Whether macOS lets the app show notifications, with a test button.
private struct NotificationPermissionRow: View {
    private var notifier: Notifier { Notifier.shared }

    var body: some View {
        HStack(spacing: 8) {
            if DesignPreview.isEnabled || notifier.permission == .allowed {
                Label("Notifications are allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Send Test") { notifier.sendTest() }
            } else if notifier.permission == .denied {
                Label("Notifications are turned off for this app", systemImage: "bell.slash.fill")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Open System Settings…") { notifier.openSystemSettings() }
            } else {
                Label("Notifications haven't been set up yet", systemImage: "bell")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Allow…") { Task { await notifier.requestPermissionIfNeeded() } }
            }
        }
        .font(.callout)
        .task { await notifier.requestPermissionIfNeeded() }
    }
}

// MARK: - Account

private struct AccountTab: View {
    let account: AccountInfo

    var body: some View {
        Form {
            Section {
                LabeledContent("claude.ai") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(account.isSignedIn ? Color.green : Color.secondary)
                            .frame(width: 7, height: 7)
                        Text(account.isSignedIn ? "Signed in" : "Signed out")
                    }
                }
                if let plan = account.plan {
                    LabeledContent("Plan", value: plan)
                }
                if let lastChecked = account.lastChecked {
                    LabeledContent("Last checked") {
                        Text(lastChecked.formatted(.relative(presentation: .named)))
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your sign-in is stored in your Mac's Keychain. The app only reads your usage; it never sends messages or changes your account.")
                        .settingsFootnote()
                    HStack {
                        Spacer()
                        if account.isSignedIn {
                            Button("Sign Out…", role: .destructive, action: account.signOut)
                        } else {
                            Button("Sign In to Claude…", action: account.signIn)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 260)
    }
}

private extension Text {
    func settingsFootnote() -> some View {
        font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
