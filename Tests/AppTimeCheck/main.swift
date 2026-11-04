// Checks for AppTimeLedger's counting rules. Run with ./scripts/test.sh

import Foundation

var failures = 0
@MainActor func check(_ name: String, _ actual: Double, _ expected: Double) {
    let ok = abs(actual - expected) < 0.001
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(name)  (got \(actual)s, expected \(expected)s)")
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/New_York")!
let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 10))!
let chat = "com.example.chat"
let tracked: Set = [chat]

/// Ticks every 5 seconds for `seconds`, with the given conditions.
@MainActor func run(_ ledger: inout AppTimeLedger, from: Date, seconds: Int, front: String? = chat,
                    idle: TimeInterval = 0, locked: Bool = false) {
    for s in stride(from: 0, through: seconds, by: 5) {
        ledger.tick(now: from.addingTimeInterval(TimeInterval(s)), frontmost: front, tracked: tracked,
                    idleSeconds: idle, screenLocked: locked, calendar: calendar)
    }
}

var a = AppTimeLedger()
run(&a, from: start, seconds: 60)
check("counts a tracked app in front", a.seconds(on: start, calendar: calendar)[chat] ?? 0, 60)

var b = AppTimeLedger()
run(&b, from: start, seconds: 60, front: "com.apple.finder")
check("ignores untracked apps", b.seconds(on: start, calendar: calendar)[chat] ?? 0, 0)

var c = AppTimeLedger()
run(&c, from: start, seconds: 60, idle: 300)
check("pauses when you've stepped away", c.seconds(on: start, calendar: calendar)[chat] ?? 0, 0)

var d = AppTimeLedger()
run(&d, from: start, seconds: 60, locked: true)
check("pauses while the screen is locked", d.seconds(on: start, calendar: calendar)[chat] ?? 0, 0)

var e = AppTimeLedger()
run(&e, from: start, seconds: 30)
run(&e, from: start.addingTimeInterval(3600), seconds: 30)  // an hour asleep in between
check("doesn't count time asleep", e.seconds(on: start, calendar: calendar)[chat] ?? 0, 60)

var f = AppTimeLedger()
let lateNight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 23, minute: 59, second: 30))!
run(&f, from: lateNight, seconds: 60)
let nextDay = lateNight.addingTimeInterval(60)
check("splits at midnight: before", f.seconds(on: lateNight, calendar: calendar)[chat] ?? 0, 30)
check("splits at midnight: after", f.seconds(on: nextDay, calendar: calendar)[chat] ?? 0, 30)

var g = AppTimeLedger()
for day in 0..<10 { run(&g, from: start.addingTimeInterval(TimeInterval(day) * 86400), seconds: 10) }
g.prune(keeping: 7)
check("keeps only the last 7 days", Double(g.days.count), 7)

let saved = try! JSONEncoder().encode(a)
let restored = try! JSONDecoder().decode(AppTimeLedger.self, from: saved)
check("survives saving and loading", restored.seconds(on: start, calendar: calendar)[chat] ?? 0, 60)

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
