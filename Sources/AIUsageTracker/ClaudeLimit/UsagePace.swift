import Foundation

/// Projects the weekly limit forward: if you keep using Claude at the same average rate
/// as so far this week, where will you be when it resets?
///
/// Pure math, no macOS calls, so the rule can be checked on its own (see Tests/PaceCheck).
enum UsagePace: Equatable {
    /// Your usage at reset if the current rate continues (under 100).
    case onTrack(projectedPercent: Double)
    /// At the current rate you'd reach 100% at this time, before the limit resets.
    case willHitLimit(at: Date)

    /// The weekly window's length.
    static let weekLength: TimeInterval = 7 * 24 * 3600
    /// Too early in the week to say anything useful (a busy first morning would look alarming).
    static let minimumElapsed: TimeInterval = 12 * 3600

    /// nil when there's nothing worth showing: the window hasn't started, it's too early
    /// to judge, or you're already at the limit (the red ring says that).
    static func project(percent: Double, resetsAt: Date?, now: Date = .now,
                        window: TimeInterval = weekLength) -> UsagePace? {
        guard let resetsAt, percent < 100 else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        let elapsed = window - remaining
        guard remaining > 0, elapsed >= minimumElapsed else { return nil }

        let ratePerSecond = max(percent, 0) / elapsed
        let projected = percent + ratePerSecond * remaining
        guard projected >= 100, ratePerSecond > 0 else {
            return .onTrack(projectedPercent: projected)
        }
        return .willHitLimit(at: now.addingTimeInterval((100 - percent) / ratePerSecond))
    }
}
