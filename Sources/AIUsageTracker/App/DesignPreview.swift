import SwiftUI

/// Launch options for reviewing the design with clearly-labeled sample data:
///   open "Peek.app" --args --design-preview [--appearance light|dark] [--snapshot <folder>]
///
/// Preview mode never reads your Keychain or contacts claude.ai.
enum DesignPreview {
    static let isEnabled = CommandLine.arguments.contains("--design-preview")

    static var appearance: NSAppearance.Name? {
        switch value(after: "--appearance") {
        case "dark": .darkAqua
        case "light": .aqua
        default: nil
        }
    }

    /// With `--snapshot <folder>`, the preview saves pictures of its own windows and quits.
    static var snapshotFolder: URL? {
        value(after: "--snapshot").map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private static func value(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Clicks the app menu's "Settings…" item, the same thing ⌘, does.
    @MainActor
    static func openSettings() {
        let appMenu = NSApp.mainMenu?.items.first?.submenu
        guard let item = appMenu?.items.first(where: { $0.keyEquivalent == "," }),
              let action = item.action
        else {
            Log.write("preview: no Settings menu item found")
            return
        }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    // MARK: - Dropdown window

    /// The dropdown's content in an ordinary window, on the same frosted material menus use.
    @MainActor private static var dropdownHosting: NSHostingView<AnyView>?

    @MainActor
    private static func panel(_ model: DashboardModel) -> AnyView {
        AnyView(UsagePanel(model: model).background(snapshotBackdrop).ignoresSafeArea())
    }

    @MainActor
    static func makeDropdownWindow() -> NSWindow {
        let hosting = NSHostingView(rootView: panel(.sample))
        dropdownHosting = hosting
        let size = hosting.fittingSize
        let frame = NSRect(origin: .zero, size: size)

        let material = NSVisualEffectView(frame: frame)
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        hosting.frame = frame
        hosting.autoresizingMask = [.width, .height]
        material.addSubview(hosting)

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Dropdown Preview"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.isMovableByWindowBackground = true
        window.contentView = material
        window.isReleasedWhenClosed = false
        window.setFrameTopLeftPoint(NSPoint(x: 120, y: (NSScreen.main?.visibleFrame.maxY ?? 900) - 20))
        return window
    }

    /// Saved pictures can't capture live frosted glass, so snapshots draw a solid stand-in
    /// that matches how the menu looks over a typical desktop.
    private static var snapshotBackdrop: Color {
        guard snapshotFolder != nil else { return .clear }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(white: 0.17, alpha: 1)
                : NSColor(white: 0.965, alpha: 1)
        })
    }

    // MARK: - Snapshots

    @MainActor
    static func saveSnapshots(dropdown: NSWindow, to folder: URL) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let mode = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "dark" : "light"

        try? await Task.sleep(for: .seconds(1.5))
        capture(dropdown.contentView, to: folder.appending(path: "dropdown-\(mode).png"))
        saveMenuBarSample(dark: mode == "dark", to: folder.appending(path: "menubar-\(mode).png"))

        // The dropdown's other states: signed out, loading, errors, and so on.
        if let hosting = dropdownHosting {
            let topLeft = NSPoint(x: dropdown.frame.minX, y: dropdown.frame.maxY)
            for (name, model) in DashboardModel.sampleStates {
                hosting.rootView = panel(model)
                try? await Task.sleep(for: .seconds(0.3))
                hosting.invalidateIntrinsicContentSize()
                hosting.layoutSubtreeIfNeeded()
                let size = hosting.fittingSize
                dropdown.setContentSize(size)
                dropdown.setFrameTopLeftPoint(topLeft)
                hosting.frame = NSRect(origin: .zero, size: size)
                try? await Task.sleep(for: .seconds(0.5))
                capture(hosting, to: folder.appending(path: "state-\(name)-\(mode).png"), trimBottom: true)
            }
        }

        for tab in SettingsTab.allCases {
            UserDefaults.standard.set(tab.rawValue, forKey: PrefKey.settingsTab)
            try? await Task.sleep(for: .seconds(1))
            let settings = NSApp.windows.first { $0.isVisible && $0 !== dropdown && $0.frame.width > 300 }
            if settings == nil {
                Log.write("preview: settings window not found; windows=\(NSApp.windows.map { "\($0.title) \($0.isVisible) \(Int($0.frame.width))" })")
            }
            // Include the title bar and tab bar for the settings window.
            capture(settings?.contentView?.superview, to: folder.appending(path: "settings-\(tab.rawValue)-\(mode).png"))
        }
        NSApp.terminate(nil)
    }

    /// The menu bar item at three usage levels, in both styles (ring only on top, ring and
    /// percentage below),
    /// drawn on menu-bar-colored strips.
    @MainActor
    private static func saveMenuBarSample(dark: Bool, to url: URL) {
        let samples: [Double] = [34, 72, 91]
        let scale: CGFloat = 2
        let rowHeight: CGFloat = 24
        let size = NSSize(width: 240, height: rowHeight * 2 + 6)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            NSColor.clear.setFill()
            NSRect(origin: .zero, size: size).fill()
            for (row, showsPercent) in [false, true].enumerated() {
                let y = size.height - CGFloat(row + 1) * rowHeight - CGFloat(row) * 6
                NSColor(white: dark ? 0.13 : 0.93, alpha: 1).setFill()
                NSRect(x: 0, y: y, width: size.width, height: rowHeight).fill()
                var x: CGFloat = 14
                for percent in samples {
                    let icon = MenuBarIcon.image(percent: percent, showsPercent: showsPercent)
                    icon.draw(in: NSRect(x: x, y: y + (rowHeight - icon.size.height) / 2, width: icon.size.width, height: icon.size.height))
                    x += icon.size.width + 28
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// - Parameter trimBottom: Cuts off empty (see-through) rows at the bottom, left over
    ///   when the dropdown shrinks between states.
    @MainActor
    private static func capture(_ view: NSView?, to url: URL, trimBottom: Bool = false) {
        guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        var output: NSBitmapImageRep = rep
        if trimBottom, let cg = rep.cgImage {
            // The backdrop is solid, so the first see-through row marks the end of the content.
            var height = rep.pixelsHigh
            for y in stride(from: rep.pixelsHigh - 1, through: 0, by: -1) {
                if (rep.colorAt(x: 4, y: y)?.alphaComponent ?? 0) > 0.5 { height = y + 1; break }
            }
            if height < rep.pixelsHigh, let cropped = cg.cropping(to: CGRect(x: 0, y: 0, width: rep.pixelsWide, height: height)) {
                output = NSBitmapImageRep(cgImage: cropped)
            }
        }
        try? output.representation(using: .png, properties: [:])?.write(to: url)
    }
}

extension View {
    /// In design-preview snapshots, draw controls as if their window were active, so
    /// sliders show the accent color instead of grey. No effect otherwise.
    @ViewBuilder func previewActiveControls() -> some View {
        if DesignPreview.isEnabled {
            environment(\.controlActiveState, .key)
        } else {
            self
        }
    }
}
