// ai-usage-hook: a tiny helper Claude Code runs on each hook event.
//
// It reads the event JSON from standard input and saves the session's latest status to
//   ~/Library/Application Support/AIUsageTracker/sessions/<session_id>.json
// where the menu bar app picks it up.
//
// Rules this program must follow:
//   - Print NOTHING to standard output. For SessionStart and UserPromptSubmit, Claude Code
//     adds a hook's printed text to Claude's conversation.
//   - Always exit 0, quickly. A hook must never block or slow down Claude Code.
//
// It also installs and removes its own entries in ~/.claude/settings.json:
//   ai-usage-hook --install [--dry-run]
//   ai-usage-hook --uninstall [--dry-run]
//   ai-usage-hook --status

import Darwin
import Foundation

let home = ProcessInfo.processInfo.environment["HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? FileManager.default.homeDirectoryForCurrentUser
let sessionsDirectory = home.appending(path: "Library/Application Support/AIUsageTracker/sessions", directoryHint: .isDirectory)
let arguments = CommandLine.arguments

if arguments.contains("--install") || arguments.contains("--uninstall") {
    exit(HookSettings.update(install: arguments.contains("--install"), dryRun: arguments.contains("--dry-run")))
} else if arguments.contains("--status") {
    print(HookSettings.status())
    exit(0)
} else {
    recordEvent()
    exit(0)
}

// MARK: - Recording events

func recordEvent() {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard let event = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
          let rawID = event["session_id"] as? String,
          let name = event["hook_event_name"] as? String
    else { return }

    // Session IDs become file names, so keep only safe characters.
    let sessionID = String(rawID.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" })
    guard !sessionID.isEmpty else { return }

    try? FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    let file = sessionsDirectory.appending(path: "\(sessionID).json")

    // Hooks can run at the same time (e.g. parallel tool calls); take turns per session.
    let lockPath = sessionsDirectory.appending(path: ".\(sessionID).lock").path
    let lock = open(lockPath, O_CREAT | O_RDWR, 0o600)
    if lock >= 0 { flock(lock, LOCK_EX) }
    defer {
        if lock >= 0 { flock(lock, LOCK_UN); close(lock) }
    }

    if name == "SessionEnd" {
        try? FileManager.default.removeItem(at: file)
        unlink(lockPath)
        return
    }

    var record = (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    let now = Date().timeIntervalSince1970

    record["session_id"] = sessionID
    if record["cwd"] == nil, let cwd = event["cwd"] as? String { record["cwd"] = cwd }
    if let entrypoint = ProcessInfo.processInfo.environment["CLAUDE_CODE_ENTRYPOINT"] { record["entrypoint"] = entrypoint }
    if let pid = claudeProcessID() { record["pid"] = pid }
    record["last_event"] = name
    record["updated_at"] = now

    if let status = status(for: name, event: event, current: record["status"] as? String),
       status != record["status"] as? String {
        record["status"] = status
        record["status_since"] = now
    }

    if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
        try? data.write(to: file, options: .atomic)
    }
}

/// Maps a hook event to the status shown in the menu. nil = leave the status as it is.
func status(for name: String, event: [String: Any], current: String?) -> String? {
    switch name {
    case "SessionStart":
        // Compacting happens mid-task; don't reset the status for it.
        return event["source"] as? String == "compact" ? nil : "idle"
    case "UserPromptSubmit", "PostToolUse", "PostToolUseFailure":
        return "working"
    case "PreToolUse":
        return event["tool_name"] as? String == "AskUserQuestion" ? "waiting_for_reply" : "working"
    case "PermissionRequest":
        return "needs_permission"
    case "Notification":
        switch event["notification_type"] as? String {
        case "permission_prompt": return "needs_permission"
        case "elicitation_dialog", "agent_needs_input": return "waiting_for_reply"
        default: return nil  // e.g. idle_prompt: Claude already finished; keep "finished"
        }
    case "Stop", "StopFailure":
        return "finished"
    default:
        return nil
    }
}

/// The Claude Code process that ran this hook, so the app can tell when a session's
/// window was closed without a clean "session ended" event. Hooks run through a shell,
/// so skip past any shell processes to find Claude Code itself.
func claudeProcessID() -> Int32? {
    var pid = getppid()
    for _ in 0..<4 {
        guard pid > 1 else { return nil }
        let name = processName(pid)
        if !["sh", "bash", "zsh", "dash"].contains(name) { return pid }
        pid = parentProcessID(of: pid)
    }
    return nil
}

func processName(_ pid: Int32) -> String {
    var buffer = [UInt8](repeating: 0, count: 256)
    let length = proc_name(pid, &buffer, UInt32(buffer.count))
    return String(decoding: buffer.prefix(Int(max(length, 0))), as: UTF8.self)
}

func parentProcessID(of pid: Int32) -> Int32 {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return 0 }
    return Int32(info.pbi_ppid)
}

// MARK: - Installing into Claude Code settings

enum HookSettings {
    static let settingsFile = home.appending(path: ".claude/settings.json")

    /// Every event the app listens to. All are documented Claude Code hook events.
    static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
        "PostToolUse", "PostToolUseFailure", "Notification", "Stop", "StopFailure", "SessionEnd",
    ]

    /// Recognizes our own entries, so removal never touches anyone else's hooks.
    static let marker = "ai-usage-hook"

    static var command: String {
        let path = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
        return "'\(path)'"
    }

    static func status() -> String {
        guard let root = readSettings(), let hooks = root["hooks"] as? [String: Any] else { return "not-installed" }
        let ours = events.filter { event in
            entries(in: hooks[event]).contains { ($0["command"] as? String)?.contains(marker) == true }
        }
        if ours.isEmpty { return "not-installed" }
        let current = events.allSatisfy { event in
            entries(in: hooks[event]).contains { ($0["command"] as? String) == command }
        }
        return current ? "installed" : "outdated"
    }

    /// Returns a process exit code: 0 = success.
    static func update(install: Bool, dryRun: Bool) -> Int32 {
        let fileExists = FileManager.default.fileExists(atPath: settingsFile.path)
        let existing: [String: Any]? = fileExists ? readSettings() : [:]
        guard var root = existing else {
            FileHandle.standardError.write(Data("Couldn't read \(settingsFile.path) as JSON; nothing changed.\n".utf8))
            return 1
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in events {
            // Drop our old entries (if any), keep everyone else's untouched.
            var groups = (hooks[event] as? [[String: Any]] ?? []).compactMap { group -> [String: Any]? in
                var group = group
                let kept = entries(in: [group]).filter { ($0["command"] as? String)?.contains(marker) != true }
                if kept.isEmpty { return nil }
                group["hooks"] = kept
                return group
            }
            if install {
                groups.append(["hooks": [["type": "command", "command": command, "timeout": 5]]])
            }
            hooks[event] = groups.isEmpty ? nil : groups
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks

        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            return 1
        }
        if dryRun {
            FileHandle.standardOutput.write(data)
            print()
            return 0
        }

        if fileExists {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let folder = settingsFile.deletingLastPathComponent()
            var backup = folder.appending(path: "settings.json.backup-\(stamp)")
            var copy = 2
            while FileManager.default.fileExists(atPath: backup.path) {
                backup = folder.appending(path: "settings.json.backup-\(stamp)-\(copy)")
                copy += 1
            }
            do {
                try FileManager.default.copyItem(at: settingsFile, to: backup)
            } catch {
                FileHandle.standardError.write(Data("Couldn't back up settings; nothing changed.\n".utf8))
                return 1
            }
            print("Backed up to \(backup.path)")
        }
        do {
            try FileManager.default.createDirectory(at: settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: settingsFile, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("Couldn't write settings: \(error.localizedDescription)\n".utf8))
            return 1
        }
        print(install ? "Installed hooks." : "Removed hooks.")
        return 0
    }

    private static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsFile) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func entries(in value: Any?) -> [[String: Any]] {
        (value as? [[String: Any]] ?? []).flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
    }
}
