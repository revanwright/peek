import Foundation

/// Adds up time spent in tracked apps, per day. Pure bookkeeping, no macOS calls,
/// so the counting rules can be checked on their own (see Tests/AppTimeCheck).
///
/// It's fed a "tick" every few seconds with what's in front and whether you're
/// actually there. Time only counts when:
///   - a tracked app is in front,
///   - the screen isn't locked,
///   - you've touched the keyboard or mouse recently, and
///   - the gap since the last tick is short (a long gap means the Mac was asleep).
struct AppTimeLedger: Codable, Equatable {
    /// Seconds per app (bundle ID) for each day ("2026-11-04").
    private(set) var days: [String: [String: Double]] = [:]

    /// Longest gap between ticks that still counts; anything longer was sleep.
    var maxGap: TimeInterval = 15
    /// No keyboard or mouse input for this long = you've stepped away.
    var idleLimit: TimeInterval = 120

    private var lastTick: Date?

    private enum CodingKeys: String, CodingKey { case days }

    mutating func tick(now: Date, frontmost: String?, tracked: Set<String>,
                       idleSeconds: TimeInterval, screenLocked: Bool, calendar: Calendar = .current) {
        defer { lastTick = now }
        guard let last = lastTick else { return }
        let elapsed = now.timeIntervalSince(last)
        guard elapsed > 0, elapsed <= maxGap,
              !screenLocked, idleSeconds < idleLimit,
              let app = frontmost, tracked.contains(app)
        else { return }
        // A stretch that crosses midnight is split between the two days.
        let midnight = calendar.startOfDay(for: now)
        if last < midnight {
            add(midnight.timeIntervalSince(last), to: app, on: last, calendar: calendar)
            add(now.timeIntervalSince(midnight), to: app, on: now, calendar: calendar)
        } else {
            add(elapsed, to: app, on: now, calendar: calendar)
        }
    }

    private mutating func add(_ seconds: TimeInterval, to app: String, on date: Date, calendar: Calendar) {
        days[Self.dayKey(for: date, calendar: calendar), default: [:]][app, default: 0] += seconds
    }

    func seconds(on date: Date, calendar: Calendar = .current) -> [String: Double] {
        days[Self.dayKey(for: date, calendar: calendar)] ?? [:]
    }

    /// Keeps only the most recent days so the saved data stays small.
    mutating func prune(keeping count: Int) {
        let keep = Set(days.keys.sorted().suffix(count))
        days = days.filter { keep.contains($0.key) }
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
