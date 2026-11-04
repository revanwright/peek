import ServiceManagement

/// Adds or removes the app from System Settings → General → Login Items.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.write("login item: \(enabled ? "on" : "off")")
        } catch {
            Log.write("login item: couldn't turn \(enabled ? "on" : "off"): \(error.localizedDescription)")
        }
    }
}
