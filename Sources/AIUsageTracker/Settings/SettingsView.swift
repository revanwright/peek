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
        }
        .formStyle(.grouped)
        .frame(height: 230)
        .onAppear { openAtLogin = LoginItem.isEnabled }
    }
}

// MARK: - Sources

private struct SourcesTab: View {
    let hooks: HookControls
    @AppStorage(PrefKey.trackClaudeLimit) private var trackLimit = true
    @AppStorage(PrefKey.trackClaudeCode) private var trackCode = true
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
            }

            Section {
                ForEach(TrackedApp.defaults) { AppSourceRow(app: $0) }
            } header: {
                Text("AI apps")
            } footer: {
                HStack {
                    Text("Time counts while the app is in front.").settingsFootnote()
                    Spacer()
                    Button("Add App…") {}
                        .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 420)
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

    var body: some View {
        Form {
            Section {
                Toggle("Warn me when I'm close to my limit", isOn: $warnEnabled)
                LabeledContent("Warn at") {
                    HStack(spacing: 10) {
                        Slider(value: $warnAt, in: 50...95, step: 5)
                            .frame(width: 170)
                        Text("\(Int(warnAt))%")
                            .monospacedDigit()
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                .disabled(!warnEnabled)
                Toggle("Notify me when my limit resets", isOn: $notifyOnReset)
            } header: {
                Text("Claude limit")
            }

            Section {
                Toggle("Notify me when a session is waiting on me", isOn: $sessionAlerts)
                Group {
                    Toggle("Needs permission", isOn: $alertPermission)
                    Toggle("Waiting for my reply", isOn: $alertReply)
                    Toggle("Finished", isOn: $alertFinished)
                }
                .padding(.leading, 18)
                .disabled(!sessionAlerts)
            } header: {
                Text("Claude Code")
            }
        }
        .formStyle(.grouped)
        .frame(height: 400)
        .animation(.smooth, value: sessionAlerts)
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
