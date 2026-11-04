import Foundation

/// Reads the status of Cowork tasks from the Claude app's own files on this Mac.
///
/// Cowork runs Claude Code with a private settings folder per task, so the app's hooks
/// never fire for it. Instead, each task keeps a small record
///   ~/Library/Application Support/Claude/local-agent-mode-sessions/<org>/<account>/local_<id>.json
/// and a log of its turns under local_<id>/.claude/projects/. The last turn in that log
/// says whether Claude is still working, asked a question, or finished. Only the turn
/// types are read; never the text of the conversation.
///
/// This relies on undocumented files, so anything unexpected is skipped quietly.
struct CoworkWatcher {
    struct Task: Equatable {
        let id: String
        let title: String
        let status: Status
        let lastActivity: Date
    }

    enum Status: Equatable {
        case working, waitingForReply, finished, idle
    }

    var baseFolder = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Claude/local-agent-mode-sessions", directoryHint: .isDirectory)
    /// Tasks with no activity for this long aren't shown.
    var recentWindow: TimeInterval = 3 * 3600
    /// A task that was mid-step but has gone quiet this long is treated as stopped.
    var staleAfter: TimeInterval = 30 * 60

    func scan(now: Date = Date()) -> [Task] {
        let fm = FileManager.default
        var tasks: [Task] = []
        for record in recordFiles() {
            let folder = record.deletingPathExtension()
            guard let transcript = newestTranscript(in: folder),
                  let modified = (try? transcript.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  now.timeIntervalSince(modified) < recentWindow,
                  let data = fm.contents(atPath: record.path),
                  let info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  info["isArchived"] as? Bool != true
            else { continue }

            var status = Self.status(fromTranscriptLines: Self.tailLines(of: transcript)) ?? .working
            if status == .working, now.timeIntervalSince(modified) > staleAfter { status = .idle }

            let title = (info["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Cowork task"
            let id = info["sessionId"] as? String ?? folder.lastPathComponent
            tasks.append(Task(id: id, title: title, status: status, lastActivity: modified))
        }
        return tasks
    }

    /// Decides a task's status from the end of its turn log (one JSON object per line).
    static func status<Lines: Collection>(fromTranscriptLines lines: Lines) -> Status? where Lines.Element: StringProtocol {
        for line in lines.reversed() {
            guard let entry = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let type = entry["type"] as? String
            else { continue }  // e.g. a line still being written

            switch type {
            case "user":
                return .working  // a new prompt or a tool's result: Claude's turn next
            case "assistant":
                let message = entry["message"] as? [String: Any] ?? [:]
                let content = message["content"] as? [[String: Any]] ?? []
                let tools = content.filter { $0["type"] as? String == "tool_use" }.compactMap { $0["name"] as? String }
                if tools.contains("AskUserQuestion") { return .waitingForReply }
                if !tools.isEmpty { return .working }
                let stop = message["stop_reason"] as? String
                return stop == "end_turn" || stop == "stop_sequence" ? .finished : .working
            default:
                continue  // bookkeeping entries (attachments, queue markers, ...)
            }
        }
        return nil
    }

    // MARK: - Files

    private func recordFiles() -> [URL] {
        let fm = FileManager.default
        let orgs = (try? fm.contentsOfDirectory(at: baseFolder, includingPropertiesForKeys: nil)) ?? []
        return orgs.flatMap { org -> [URL] in
            let accounts = (try? fm.contentsOfDirectory(at: org, includingPropertiesForKeys: nil)) ?? []
            return accounts.flatMap { account -> [URL] in
                ((try? fm.contentsOfDirectory(at: account, includingPropertiesForKeys: nil)) ?? [])
                    .filter { $0.lastPathComponent.hasPrefix("local_") && $0.pathExtension == "json" }
            }
        }
    }

    private func newestTranscript(in folder: URL) -> URL? {
        let fm = FileManager.default
        let projects = folder.appending(path: ".claude/projects", directoryHint: .isDirectory)
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = ((try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [])
            .flatMap { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: keys)) ?? [] }
            .filter { $0.pathExtension == "jsonl" }
        return files.max { a, b in
            let da = (try? a.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
            let db = (try? b.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
            return da < db
        }
    }

    /// The last lines of a file, reading only its final 64 KB.
    static func tailLines(of file: URL, bytes: UInt64 = 64 * 1024) -> [Substring] {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > bytes ? size - bytes : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        var lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        if size > bytes, !lines.isEmpty { lines.removeFirst() }  // probably cut mid-line
        return lines
    }
}
