import Foundation

enum Countdown {
    /// "2h 13m" or "13m".
    static func short(to date: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSinceNow / 60))
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
