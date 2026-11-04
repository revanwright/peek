// Checks for CoworkWatcher. Run with ./scripts/test.sh
// 1) Status rules, on small hand-written turn logs.
// 2) A read-only pass over the real Cowork tasks on this Mac (counts only, no text).

import Foundation

var failures = 0
@MainActor func check(_ name: String, _ actual: CoworkWatcher.Status?, _ expected: CoworkWatcher.Status?) {
    let ok = actual == expected
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(name)  (got \(String(describing: actual)), expected \(String(describing: expected)))")
}

let prompt = #"{"type":"user","message":{"role":"user","content":"hi"}}"#
let toolResult = #"{"type":"user","message":{"content":[{"type":"tool_result"}]}}"#
let done = #"{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text"}]}}"#
let usingTool = #"{"type":"assistant","message":{"stop_reason":"tool_use","content":[{"type":"text"},{"type":"tool_use","name":"Bash"}]}}"#
let asking = #"{"type":"assistant","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","name":"AskUserQuestion"}]}}"#
let bookkeeping = #"{"type":"last-prompt","leafUuid":"x"}"#
let halfWritten = #"{"type":"assistant","message":{"stop_re"#

check("finished reply", CoworkWatcher.status(fromTranscriptLines: [prompt, done]), .finished)
check("finished reply, then bookkeeping", CoworkWatcher.status(fromTranscriptLines: [prompt, done, bookkeeping]), .finished)
check("new prompt sent", CoworkWatcher.status(fromTranscriptLines: [done, prompt]), .working)
check("running a tool", CoworkWatcher.status(fromTranscriptLines: [prompt, usingTool]), .working)
check("tool finished, Claude's turn", CoworkWatcher.status(fromTranscriptLines: [usingTool, toolResult]), .working)
check("asked a question", CoworkWatcher.status(fromTranscriptLines: [prompt, asking]), .waitingForReply)
check("ignores a half-written line", CoworkWatcher.status(fromTranscriptLines: [prompt, done, halfWritten]), .finished)
check("empty log", CoworkWatcher.status(fromTranscriptLines: [String]()), nil)

// Real data, read-only. Shows every task regardless of age, so old tasks can be checked.
var watcher = CoworkWatcher()
watcher.recentWindow = .infinity
watcher.staleAfter = .infinity
let tasks = watcher.scan()
let counts = Dictionary(grouping: tasks, by: { "\($0.status)" }).mapValues(\.count)
print("\nReal Cowork tasks on this Mac (not archived): \(tasks.count) → \(counts)")
if let newest = tasks.max(by: { $0.lastActivity < $1.lastActivity }) {
    print("Most recent: \(newest.lastActivity.formatted()) status=\(newest.status)")
}

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
