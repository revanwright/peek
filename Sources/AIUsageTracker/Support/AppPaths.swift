import Foundation

/// Folders the app shares with its command-line helpers (Claude Code hooks).
enum AppPaths {
    static let supportDirectory: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/AIUsageTracker", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}
