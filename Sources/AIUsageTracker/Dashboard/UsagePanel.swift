import SwiftUI

/// The dropdown that opens from the menu bar icon.
struct UsagePanel: View {
    let model: DashboardModel
    var onSignIn: () -> Void = {}
    var onRetry: () -> Void = {}
    /// Called each time the dropdown opens (used to refresh).
    var onOpen: () -> Void = {}
    var onOpenSession: (DashboardModel.CodeSession) -> Void = { _ in }

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isSample { SampleBadge() }

            claudeSection

            if let sessions = model.sessions { SessionsSection(sessions: sessions, onOpen: onOpenSession) }
            if let apps = model.apps { AppsSection(apps: apps) }

            footer
        }
        .padding(Theme.panelPadding)
        .frame(width: Theme.panelWidth)
        .animation(.smooth(duration: 0.25), value: model.stateKey)
        .onAppear(perform: onOpen)
    }

    @ViewBuilder private var claudeSection: some View {
        switch model.claude {
        case .disabled:
            EmptyView()
        case .signedOut:
            SignInCard(onSignIn: onSignIn)
        case .loading:
            MessageCard(symbol: nil, title: "Reading your Claude usage…", detail: nil)
        case .unavailable(let message):
            MessageCard(symbol: "exclamationmark.triangle.fill", title: "Couldn't read your Claude usage", detail: message) {
                Button("Try Again", action: onRetry)
            }
        case .ready(let limit, let warning):
            ClaudeLimitCard(limit: limit, warning: warning)
        }
    }

    private var footer: some View {
        HStack(spacing: 2) {
            if let updatedAt = model.updatedAt {
                TimelineView(.everyMinute) { _ in
                    Text("Updated \(updatedAt.formatted(.relative(presentation: .named)))")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            IconButton(symbol: "gearshape", help: "Settings…") {
                NSApp.activate()
                openSettings()
            }
            IconButton(symbol: "power", help: "Quit AI Usage Tracker") {
                NSApp.terminate(nil)
            }
        }
        .padding(.leading, 4)
    }
}

private extension DashboardModel {
    /// Changes whenever the top card switches state, so the switch animates.
    var stateKey: String {
        switch claude {
        case .disabled: "disabled"
        case .signedOut: "signedOut"
        case .loading: "loading"
        case .unavailable: "unavailable"
        case .ready(_, let warning): warning == nil ? "ready" : "stale"
        }
    }
}

// MARK: - Claude limit

private struct ClaudeLimitCard: View {
    let limit: DashboardModel.ClaudeLimit
    let warning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                AppIconView(bundleID: "com.anthropic.claudefordesktop", fallbackSymbol: "sparkle", size: 20)
                Text("Claude").font(.headline)
                if let plan = limit.plan { PlanBadge(text: plan) }
                Spacer()
            }

            HStack(alignment: .top, spacing: 0) {
                LimitRing(
                    title: "Current session",
                    window: limit.session,
                    resetText: { "Resets in \(Countdown.short(to: $0))" }
                )
                .help("5-hour limit, shared across Claude on the web, the desktop app, and Claude Code")

                if let weekly = limit.weekly {
                    LimitRing(
                        title: "Weekly",
                        window: weekly,
                        resetText: { "Resets \($0.formatted(.dateTime.weekday(.abbreviated).hour().minute()))" }
                    )
                }
            }

            if let warning {
                Label("Showing your last reading. \(warning)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.cardPadding)
        .card()
    }
}

/// One limit: a ring with its name and reset time underneath.
private struct LimitRing: View {
    let title: String
    let window: DashboardModel.ClaudeLimit.Window
    let resetText: (Date) -> String

    var body: some View {
        VStack(spacing: 10) {
            RingGauge(percent: window.percent, level: UsageLevel(percent: window.percent))
            VStack(spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                TimelineView(.everyMinute) { _ in
                    Text(window.resetsAt.map(resetText) ?? "Not started yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SignInCard: View {
    let onSignIn: () -> Void

    var body: some View {
        MessageCard(
            symbol: "person.crop.circle.badge.questionmark",
            title: "Sign in to see your Claude limit",
            detail: "Your sign-in stays in your Mac's Keychain."
        ) {
            Button("Sign In to Claude…", action: onSignIn)
                .buttonStyle(.borderedProminent)
        }
    }
}

/// A centered card for loading, error, and signed-out states.
private struct MessageCard<Actions: View>: View {
    let symbol: String?
    let title: String
    let detail: String?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions().padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, Theme.cardPadding)
        .card()
    }
}

extension MessageCard where Actions == EmptyView {
    init(symbol: String?, title: String, detail: String?) {
        self.init(symbol: symbol, title: title, detail: detail) { EmptyView() }
    }
}

// MARK: - Claude Code sessions

private struct SessionsSection: View {
    let sessions: [DashboardModel.CodeSession]
    let onOpen: (DashboardModel.CodeSession) -> Void

    var body: some View {
        let sorted = sessions.sorted { ($0.status.sortOrder, $1.since) < ($1.status.sortOrder, $0.since) }
        let needYou = sessions.filter { $0.status == .needsPermission || $0.status == .waitingForReply }.count

        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Claude Code", detail: needYou > 0 ? "\(needYou) need\(needYou == 1 ? "s" : "") you" : nil,
                          detailTint: .orange)
            VStack(spacing: 0) {
                if sorted.isEmpty {
                    Text("No active sessions")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    ForEach(sorted) { session in
                        SessionRow(session: session) { onOpen(session) }
                    }
                }
            }
            .padding(4)
            .card()
        }
    }
}

private struct SessionRow: View {
    let session: DashboardModel.CodeSession
    let onOpen: () -> Void
    @State private var isHovering = false

    var body: some View {
        let status = session.status
        let needsYou = status == .needsPermission || status == .waitingForReply

        HStack(spacing: 10) {
            StatusBadge(status: status)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.project)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(status.title)
                        .foregroundStyle(needsYou ? AnyShapeStyle(status.tint) : AnyShapeStyle(.secondary))
                    if let client = session.client {
                        Text("· \(client)").foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            TimelineView(.everyMinute) { _ in
                Text(shortElapsed(since: session.since))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(isHovering ? Theme.hoverFill : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(session.project), \(status.title)")
    }

    private func shortElapsed(since date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        switch minutes {
        case ..<1: return "now"
        case ..<60: return "\(minutes)m"
        default: return "\(minutes / 60)h"
        }
    }
}

private struct StatusBadge: View {
    let status: DashboardModel.CodeSession.Status

    var body: some View {
        ZStack {
            Circle().fill(status.tint.opacity(0.16))
            symbol
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(status.tint)
        }
        .frame(width: 26, height: 26)
    }

    @ViewBuilder private var symbol: some View {
        if status == .working {
            Image(systemName: status.symbol)
                .symbolEffect(.rotate, options: .repeat(.continuous))
        } else {
            Image(systemName: status.symbol)
        }
    }
}

// MARK: - Other AI apps

private struct AppsSection: View {
    let apps: [DashboardModel.AppTime]

    var body: some View {
        let total = apps.reduce(0) { $0 + $1.seconds }

        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "AI Apps Today", detail: total > 0 ? formatDuration(total) : nil)
            VStack(spacing: 0) {
                if apps.isEmpty {
                    Text("No time in other AI apps yet today")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    ForEach(apps.sorted { $0.seconds > $1.seconds }) { app in
                        HStack(spacing: 10) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 22, height: 22)
                            Text(app.name).font(.system(size: 13))
                            Spacer()
                            Text(formatDuration(app.seconds))
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                    }
                }
            }
            .padding(4)
            .card()
        }
    }
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds / 60)
    let h = minutes / 60, m = minutes % 60
    if h == 0 { return "\(m)m" }
    return m == 0 ? "\(h)h" : "\(h)h \(m)m"
}

// MARK: - Building blocks

private struct SectionHeader: View {
    let title: String
    var detail: String?
    var detailTint: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(detailTint)
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct PlanBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .foregroundStyle(.secondary)
    }
}

private struct SampleBadge: View {
    var body: some View {
        Label("Sample data — design preview", systemImage: "eye")
            .font(.caption.weight(.medium))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.orange.opacity(0.12)))
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(isHovering ? Theme.hoverFill : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}

struct AppIconView: View {
    let bundleID: String
    let fallbackSymbol: String
    let size: CGFloat

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallbackSymbol)
                .frame(width: size, height: size)
        }
    }
}

extension View {
    /// The raised, rounded "module" look used for each section of the dropdown.
    func card() -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        return background(shape.fill(Theme.cardFill))
            .overlay(shape.strokeBorder(Theme.cardStroke, lineWidth: 0.5))
    }
}
