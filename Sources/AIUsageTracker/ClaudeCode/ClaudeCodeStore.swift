import AppKit
import Observation

/// Live list of Claude Code sessions, built from the files the hook helper writes to
/// ~/Library/Application Support/AIUsageTracker/sessions/.
@Observable
@MainActor
final class ClaudeCodeStore {
    struct Session: Identifiable, Equatable {
        enum Status: String {
            case idle
            case working
            case needsPermission = "needs_permission"
            case waitingForReply = "waiting_for_reply"
            case finished
        }

        let id: String
        let cwd: String
        let status: Status
        let since: Date
        let entrypoint: String?
        /// Shown instead of the folder name (Cowork tasks use their title).
        var name: String? = nil

        /// The app the session runs in, for display ("VS Code", ...). nil if unknown.
        var clientName: String? {
            switch entrypoint {
            case "claude-vscode": "VS Code"
            case "claude-desktop": "the Claude app"
            case "local-agent": "Cowork"
            case "cli": "Terminal"
            default: nil
            }
        }

        /// Sessions that run inside the Claude desktop app (its Code tab, or Cowork).
        var isInClaudeApp: Bool { entrypoint == "claude-desktop" || entrypoint == "local-agent" }

        var project: String {
            if let name { return name }
            let folder = URL(fileURLWithPath: cwd).standardizedFileURL
            if folder == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL { return "Home" }
            return folder.lastPathComponent
        }
    }

    enum HookStatus: Equatable {
        case unknown, installed, notInstalled, outdated, failed(String)
    }

    private(set) var sessions: [Session] = []
    private var hookSessions: [Session] = []
    private var coworkSessions: [Session] = []
    private let cowork = CoworkWatcher()
    private var coworkTask: Task<Void, Never>?
    private(set) var hookStatus: HookStatus = .unknown

    var isEnabled: Bool { Preferences.isOn(PrefKey.trackClaudeCode) }

    private let folder = AppPaths.supportDirectory.appending(path: "sessions", directoryHint: .isDirectory)
    private var watcher: DispatchSourceFileSystemObject?
    private var sweepTask: Task<Void, Never>?

    init() {
        guard !DesignPreview.isEnabled else { return }
        Notifier.shared.openSession = { [weak self] id in
            guard let self, let session = sessions.first(where: { $0.id == id }) else { return }
            open(session)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        watchFolder()
        reload()
        // Catches sessions whose window was closed without a clean "ended" event.
        sweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                self?.reload()
            }
        }
        Task { await checkHooks() }
        // Cowork has no hooks; its task logs are checked every few seconds instead.
        coworkTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.reloadCowork()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    var isCoworkEnabled: Bool { Preferences.isOn(PrefKey.trackCowork) }

    private func reloadCowork() async {
        guard isCoworkEnabled else {
            if !coworkSessions.isEmpty { coworkSessions = []; publish() }
            return
        }
        let watcher = cowork
        let tasks = await Task.detached { watcher.scan() }.value
        let found = tasks.map { task in
            Session(
                id: "cowork-\(task.id)",
                cwd: "",
                status: Session.Status(task.status),
                since: task.lastActivity,
                entrypoint: "local-agent",
                name: task.title
            )
        }
        if found != coworkSessions {
            coworkSessions = found
            publish()
        }
    }

    // MARK: - Reading sessions

    private func watchFolder() {
        let descriptor = Darwin.open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var found: [Session] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let id = record["session_id"] as? String,
                  let cwd = record["cwd"] as? String
            else { continue }

            let updated = Date(timeIntervalSince1970: (record["updated_at"] as? NSNumber)?.doubleValue ?? 0)
            if isGone(pid: (record["pid"] as? NSNumber)?.int32Value, lastUpdate: updated) {
                try? FileManager.default.removeItem(at: file)
                continue
            }

            let status = (record["status"] as? String).flatMap(Session.Status.init) ?? .idle
            let since = (record["status_since"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? updated
            found.append(Session(id: id, cwd: cwd, status: status, since: since, entrypoint: record["entrypoint"] as? String))
        }
        guard found != hookSessions else { return }
        hookSessions = found
        publish()
    }

    /// Combines hook-reported and Cowork sessions, and nudges about any whose status changed.
    private func publish() {
        let combined = (hookSessions + coworkSessions).sorted { $0.since > $1.since }
        guard combined != sessions else { return }
        // Only status *changes* nudge; sessions seen for the first time (including
        // everything found when the app starts) don't.
        let previous = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.status) })
        for session in combined {
            if let before = previous[session.id], before != session.status {
                Notifier.shared.sessionChanged(session)
            }
        }
        sessions = combined
    }

    /// A session is gone when its Claude Code process has exited, or (if we never
    /// learned the process) when it hasn't been heard from in 12 hours.
    private func isGone(pid: Int32?, lastUpdate: Date) -> Bool {
        if let pid, pid > 1 {
            return kill(pid, 0) != 0 && errno == ESRCH
        }
        return Date().timeIntervalSince(lastUpdate) > 12 * 3600
    }

    // MARK: - Opening a session

    /// Brings the session's window forward: VS Code opens that project's window,
    /// the Claude desktop app is brought to the front.
    func open(_ session: Session) {
        let workspace = NSWorkspace.shared
        switch session.entrypoint {
        case "claude-vscode":
            guard let vscode = workspace.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") else { return }
            workspace.open([URL(fileURLWithPath: session.cwd)], withApplicationAt: vscode, configuration: NSWorkspace.OpenConfiguration())
        case "claude-desktop", "local-agent":
            if let claude = workspace.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") {
                workspace.openApplication(at: claude, configuration: NSWorkspace.OpenConfiguration())
            }
        default:
            if let terminal = workspace.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                workspace.openApplication(at: terminal, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    // MARK: - Hooks

    private var helper: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Helpers/ai-usage-hook")
    }

    func checkHooks() async {
        let result = await run(["--status"])
        switch result.output.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "installed": hookStatus = .installed
        case "outdated": hookStatus = .outdated
        case "not-installed": hookStatus = .notInstalled
        default: hookStatus = .failed(result.output)
        }
    }

    func installHooks() async { await change("--install") }
    func removeHooks() async { await change("--uninstall") }

    private func change(_ flag: String) async {
        let result = await run([flag])
        Log.write("hooks \(flag): exit \(result.code) \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        if result.code != 0 {
            hookStatus = .failed(result.output)
            return
        }
        await checkHooks()
    }

    private func run(_ arguments: [String]) async -> (code: Int32, output: String) {
        let helper = helper
        return await Task.detached {
            let process = Process()
            process.executableURL = helper
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                return (-1, error.localizedDescription)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }
}

extension ClaudeCodeStore.Session.Status {
    init(_ status: CoworkWatcher.Status) {
        switch status {
        case .working: self = .working
        case .waitingForReply: self = .waitingForReply
        case .finished: self = .finished
        case .idle: self = .idle
        }
    }
}
