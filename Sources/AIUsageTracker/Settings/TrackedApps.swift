import AppKit
import Observation
import UniformTypeIdentifiers

/// The list of AI apps whose time is tracked. Starts with ChatGPT and Muse;
/// you can add any app from Settings → Sources, or remove one by right-clicking it.
@Observable
@MainActor
final class TrackedApps {
    static let shared = TrackedApps()

    private(set) var apps: [TrackedApp]

    private static let storageKey = "trackedApps"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([TrackedApp].self, from: data) {
            apps = saved
        } else {
            apps = TrackedApp.defaults
        }
    }

    /// Shows a standard "choose an app" panel, starting in Applications.
    func chooseAndAdd() {
        let panel = NSOpenPanel()
        panel.title = "Add an AI App"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(add)
    }

    func add(_ url: URL) {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        guard id != Bundle.main.bundleIdentifier, !apps.contains(where: { $0.bundleID == id }) else { return }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        apps.append(TrackedApp(bundleID: id, name: name))
        save()
    }

    func remove(_ app: TrackedApp) {
        apps.removeAll { $0.bundleID == app.bundleID }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(apps) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
