// Checks for UsagePace's weekly projection. Run with ./scripts/test.sh

import Foundation

var failures = 0
@MainActor func check(_ name: String, _ ok: Bool, _ detail: String) {
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(name)  (\(detail))")
}

let now = Date(timeIntervalSince1970: 1_800_000_000)
let day: TimeInterval = 24 * 3600
func resets(inDays days: Double) -> Date { now.addingTimeInterval(days * day) }

// Halfway through the week at 40% → about 80% by reset.
let half = UsagePace.project(percent: 40, resetsAt: resets(inDays: 3.5), now: now)
if case .onTrack(let p)? = half {
    check("halfway at 40% is on track for 80%", abs(p - 80) < 0.01, "projected \(p)")
} else { check("halfway at 40% is on track for 80%", false, "\(String(describing: half))") }

// Halfway through at 60% → would hit 100% two-thirds of the way through the rest.
let hot = UsagePace.project(percent: 60, resetsAt: resets(inDays: 3.5), now: now)
if case .willHitLimit(let at)? = hot {
    let hours = at.timeIntervalSince(now) / 3600
    // 60% over 84h = 0.714%/h; 40% more takes 56h.
    check("halfway at 60% hits the limit in 56 hours", abs(hours - 56) < 0.01, "\(hours)h")
} else { check("halfway at 60% hits the limit in 56 hours", false, "\(String(describing: hot))") }

// Exactly on pace for 100% at reset counts as hitting it (at reset time).
let edge = UsagePace.project(percent: 50, resetsAt: resets(inDays: 3.5), now: now)
if case .willHitLimit(let at)? = edge {
    check("50% at halfway hits the limit right at reset", abs(at.timeIntervalSince(resets(inDays: 3.5))) < 1, "at reset")
} else { check("50% at halfway hits the limit right at reset", false, "\(String(describing: edge))") }

check("says nothing in the first 12 hours",
      UsagePace.project(percent: 30, resetsAt: resets(inDays: 6.8), now: now) == nil, "nil")
check("says nothing once at the limit",
      UsagePace.project(percent: 100, resetsAt: resets(inDays: 2), now: now) == nil, "nil")
check("says nothing before the window starts",
      UsagePace.project(percent: 0, resetsAt: nil, now: now) == nil, "nil")
check("zero usage is on track for 0%",
      UsagePace.project(percent: 0, resetsAt: resets(inDays: 3), now: now) == .onTrack(projectedPercent: 0), "0%")

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
