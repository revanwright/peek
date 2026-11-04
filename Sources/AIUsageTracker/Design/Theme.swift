import SwiftUI

/// Shared look-and-feel values so every screen uses the same spacing, shapes, and colors.
enum Theme {
    static let panelWidth: CGFloat = 320
    static let panelPadding: CGFloat = 12
    static let cardPadding: CGFloat = 12
    static let cardRadius: CGFloat = 12
    static let rowRadius: CGFloat = 7

    /// A soft fill that reads as a raised "card" on top of the menu's frosted glass,
    /// in both light and dark mode (like Control Center's modules).
    static let cardFill = Color.primary.opacity(0.045)
    static let cardStroke = Color.primary.opacity(0.06)
    static let trackFill = Color.primary.opacity(0.09)
    static let hoverFill = Color.primary.opacity(0.06)
}

/// How close you are to a limit. Drives ring colors in the dropdown and menu bar.
/// Red starts at your warning level (Settings → Notifications); orange starts at 60%,
/// or a little before your warning level if you've set it lower than that.
enum UsageLevel {
    case comfortable, elevated, critical

    init(percent: Double, alertThreshold: Double = AlertSettings.warnAtPercent) {
        if percent >= alertThreshold {
            self = .critical
        } else if percent >= min(60, alertThreshold - 10) {
            self = .elevated
        } else {
            self = .comfortable
        }
    }

    var color: Color {
        switch self {
        case .comfortable: .green
        case .elevated: .orange
        case .critical: .red
        }
    }

    var nsColor: NSColor {
        switch self {
        case .comfortable: .systemGreen
        case .elevated: .systemOrange
        case .critical: .systemRed
        }
    }
}

extension DashboardModel.CodeSession.Status {
    var title: String {
        switch self {
        case .working: "Working"
        case .needsPermission: "Needs permission"
        case .waitingForReply: "Waiting for your reply"
        case .finished: "Finished"
        }
    }

    var symbol: String {
        switch self {
        case .working: "arrow.triangle.2.circlepath"
        case .needsPermission: "hand.raised.fill"
        case .waitingForReply: "bubble.left.fill"
        case .finished: "checkmark"
        }
    }

    var tint: Color {
        switch self {
        case .working: .blue
        case .needsPermission: .orange
        case .waitingForReply: .purple
        case .finished: .green
        }
    }

    /// Sessions that need you sort to the top.
    var sortOrder: Int {
        switch self {
        case .needsPermission: 0
        case .waitingForReply: 1
        case .working: 2
        case .finished: 3
        }
    }
}
