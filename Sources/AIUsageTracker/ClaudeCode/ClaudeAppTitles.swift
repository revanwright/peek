import Foundation

/// Titles and IDs of Claude Code sessions in the Claude desktop app ("Chat A", "Fix login bug", ...).
///
/// Several sessions often share a project folder, so the folder name alone can't tell
/// them apart. The Claude app saves each Code-tab session as a small file under
/// `~/Library/Application Support/Claude/claude-code-sessions/<account>/<org>/local_*.json`,
/// with its `title` and `cliSessionId`, the same session ID Claude Code's hooks report.
/// Its own `sessionId` ("local_...") opens that exact session through the link the
/// Claude app's Dock menu uses: `claude://code/continue?session=<sessionId>`.
/// This is the Claude app's private storage (read only, never changed), so if its layout
/// changes, rows simply fall back to the folder name.
@MainActor
enum ClaudeAppTitles {
    struct Info: Equatable {
        let title: String?
        /// The Claude app's own ID for the session ("local_...").
        let appSessionID: String?
    }

    private static var cache: [String: (modified: Date, cliID: String, info: Info)] = [:]

    /// Session ID (as hooks report it) → title and app ID, for the Claude app's Code sessions.
    static func load() -> [String: Info] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
        var titles: [String: Info] = [:]
        var seen = Set<String>()
        for account in subfolders(of: root) {
            for org in subfolders(of: account) {
                let files = (try? FileManager.default.contentsOfDirectory(
                    at: org, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
                for file in files where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
                    let path = file.path
                    seen.insert(path)
                    let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? .distantPast
                    if let hit = cache[path], hit.modified == modified {
                        titles[hit.cliID] = hit.info
                        continue
                    }
                    guard let data = try? Data(contentsOf: file),
                          let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                          let cliID = record["cliSessionId"] as? String
                    else { continue }
                    let title = (record["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let info = Info(title: title?.isEmpty == false ? title : nil,
                                    appSessionID: (record["sessionId"] as? String).flatMap(validAppID))
                    cache[path] = (modified, cliID, info)
                    titles[cliID] = info
                }
            }
        }
        cache = cache.filter { seen.contains($0.key) }
        return titles
    }

    /// Only IDs shaped like the Claude app's own ("local_" + letters, digits, dashes) go into a link.
    private static func validAppID(_ id: String) -> String? {
        guard id.hasPrefix("local_"), id.count <= 80,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        return id
    }

    private static func subfolders(of url: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }
}
