import Foundation

/// One usage window from claude.ai, e.g. the rolling 5-hour limit or the weekly limit.
struct UsageWindow: Sendable, Equatable {
    let key: String
    /// The number exactly as claude.ai reports it (expected 0–100; verified during testing).
    let utilization: Double
    let resetsAt: Date?
}

/// Everything claude.ai's usage endpoint returned at one moment.
struct UsageSnapshot: Sendable, Equatable {
    let windows: [String: UsageWindow]
    let fetchedAt: Date

    var fiveHour: UsageWindow? { windows["five_hour"] }
    var weekly: UsageWindow? { windows["seven_day"] }

    /// Reads the JSON from `/api/organizations/{id}/usage`. Any entry shaped like
    /// `{ "utilization": number, "resets_at": date-or-null }` becomes a window, so new
    /// window types Anthropic adds later still show up without code changes.
    static func parse(_ data: Data, fetchedAt: Date = .now) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.unexpectedShape
        }
        var windows: [String: UsageWindow] = [:]
        for (key, value) in root {
            guard let entry = value as? [String: Any],
                  let utilization = (entry["utilization"] as? NSNumber)?.doubleValue
            else { continue }
            windows[key] = UsageWindow(
                key: key,
                utilization: utilization,
                resetsAt: (entry["resets_at"] as? String).flatMap(parseDate)
            )
        }
        guard !windows.isEmpty else { throw ParseError.unexpectedShape }
        return UsageSnapshot(windows: windows, fetchedAt: fetchedAt)
    }

    enum ParseError: LocalizedError {
        case unexpectedShape
        var errorDescription: String? { "claude.ai sent usage data in a format the app doesn't recognize." }
    }

    private static func parseDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
