import AppKit
import WebKit

/// A small window showing claude.ai's real sign-in page. As soon as claude.ai
/// hands back a session key, the window closes and reports it.
@MainActor
final class SignInWindowController: NSObject, NSWindowDelegate, WKUIDelegate {
    private let window: NSWindow
    private let webView: WKWebView
    private var watchTask: Task<Void, Never>?
    private let onSignedIn: (String) -> Void
    private let onClose: () -> Void
    private var didFinish = false

    init(onSignedIn: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.onSignedIn = onSignedIn
        self.onClose = onClose

        let frame = NSRect(x: 0, y: 0, width: 480, height: 720)
        webView = WKWebView(frame: frame, configuration: ClaudeWebSession.shared.makeConfiguration())
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to Claude"
        window.contentView = webView
        window.isReleasedWhenClosed = false
        super.init()

        window.delegate = self
        webView.uiDelegate = self
    }

    func show() {
        Task {
            // Start from a clean slate so an old, expired key can't be mistaken for a new one.
            await ClaudeWebSession.shared.clear()
            webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        }
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        watchForSessionKey()
    }

    private func watchForSessionKey() {
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                let stillOnLoginPage = webView.url?.path.hasPrefix("/login") ?? true
                if !stillOnLoginPage,
                   let key = await ClaudeWebSession.shared.cookieValue(named: "sessionKey"),
                   !key.isEmpty {
                    finish(with: key)
                    return
                }
            }
        }
    }

    private func finish(with key: String) {
        guard !didFinish else { return }
        didFinish = true
        Log.write("sign-in: session key received")
        onSignedIn(key)
        window.close()
    }

    // Some sign-in buttons try to open a pop-up window; show those pages in place instead.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func windowWillClose(_ notification: Notification) {
        watchTask?.cancel()
        onClose()
    }
}
