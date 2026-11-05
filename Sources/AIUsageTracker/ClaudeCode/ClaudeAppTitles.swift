import Foundation

/// Titles of Claude Code sessions in the Claude desktop app ("Chat A", "Fix login bug", ...).
///
/// Several sessions often share a project folder, so the folder name alone can't tell
/// them apart. The Claude app saves each Code-tab session as a small file under
/// `~/Library/Application Support/Claude/claude-code-sessions/<account>/<org>/local_*.json`,
/// with its `title` and `cliSessionId`, the same session ID Claude Code's hooks report.
/// This is the Claude app's private storage (read only, never changed), so if its layout
/// changes, rows simply fall back to the folder name.
@MainActor
enum ClaudeAppTitles {
    private static var cache: [String: (modified: Date, cliID: String, title: String)] = [:]

    /// Session ID (as hooks report it) → title, for the Claude app's Code sessions.
    static func load() -> [String: String] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
        var titles: [String: String] = [:]
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
                        titles[hit.cliID] = hit.title
                        continue
                    }
                    guard let data = try? Data(contentsOf: file),
                          let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                          let cliID = record["cliSessionId"] as? String,
                          let title = (record["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !title.isEmpty
                    else { continue }
                    cache[path] = (modified, cliID, title)
                    titles[cliID] = title
                }
            }
        }
        cache = cache.filter { seen.contains($0.key) }
        return titles
    }

    private static func subfolders(of url: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }
}
