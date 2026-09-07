import AppKit
import Combine
import SwiftUI
import WebKit

@MainActor
final class PlayerController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    @Published private(set) var isWallpaper = false
    @Published private(set) var hasVideo = false
    @Published private(set) var isPaused = true
    @Published private(set) var status = "アプリ内のYouTubeで動画を選んでください。"
    @Published private(set) var pageAddress = ""
    @Published private(set) var volume = 50.0
    @Published var screenID: CGDirectDisplayID = 0 { didSet { moveWallpaper() } }
    @Published private(set) var screens = NSScreen.screens
    let webView: WKWebView
    let browserContainer = NSView()
    private(set) var wallpaper: WallpaperWindow?
    private var browserWindow: NSWindow?
    private var addressObservation: NSKeyValueObservation?
    private var settingsRevision = 0
    private var presentationRevision = 0

    init(dataStore: WKWebsiteDataStore? = nil) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore ?? .default()
        configuration.applicationNameForUserAgent = "MornDesktopTube/0.2"
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.userContentController.addUserScript(WKUserScript(
            source: PlayerScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        attach(to: browserContainer)
        addressObservation = webView.observe(\.url, options: [.new]) { [weak self] view, _ in
            Task { @MainActor in self?.pageAddress = view.url?.absoluteString ?? "" }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    static func youtubeURL(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let url = URL(string: text.contains("://") ? text : "https://" + text),
              isSecureNavigation(url),
              ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"].contains(url.host?.lowercased() ?? "") else { return nil }
        return url
    }

    static func isSecureNavigation(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host != nil && url.user == nil && url.password == nil
    }

    func openYouTube(_ input: String = "https://www.youtube.com/") {
        guard let url = Self.youtubeURL(input) else {
            status = "httpsのYouTube URLを入力してください。"
            return
        }
        showBrowser()
        webView.load(URLRequest(url: url))
    }

    func showBrowser() {
        presentationRevision += 1
        isWallpaper = false
        wallpaper?.orderOut(nil)
        attach(to: browserContainer)
        configurePlayer()
        if browserWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 740),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "MornDesktopTube — YouTube"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 640, height: 420)
            window.contentView = NSHostingView(rootView: BrowserView(controller: self))
            window.delegate = self
            window.center()
            browserWindow = window
        }
        browserWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if webView.url == nil { webView.load(URLRequest(url: URL(string: "https://www.youtube.com/")!)) }
        status = "動画を選んで「背景に表示」を押してください。"
    }

    func showWallpaper() async {
        presentationRevision += 1
        let current = presentationRevision
        await refreshPlayback()
        guard current == presentationRevision else { return }
        guard hasVideo, let screen = targetScreen else {
            status = "アプリ内のYouTubeで動画を開いてください。"
            return
        }
        if wallpaper == nil { wallpaper = WallpaperWindow(screen: screen) }
        guard let container = wallpaper?.contentView else { return }
        isWallpaper = true
        attach(to: container)
        moveWallpaper()
        configurePlayer()
        wallpaper?.orderBack(nil)
        browserWindow?.orderOut(nil)
        status = "背景に表示中"
    }

    func stop() async {
        presentationRevision += 1
        let current = presentationRevision
        isWallpaper = false
        isPaused = true
        wallpaper?.orderOut(nil)
        attach(to: browserContainer)
        configurePlayer()
        status = "背景と再生を停止しました。"
        await webView.pauseAllMediaPlayback()
        guard current == presentationRevision else { return }
        await refreshPlayback()
    }

    func windowWillClose(_ notification: Notification) {
        guard !isWallpaper else { return }
        Task { await stop() }
    }

    func setVolume(_ value: Double) {
        guard value.isFinite else { return }
        volume = min(100, max(0, value))
        configurePlayer()
    }

    func togglePlayback() async {
        do {
            let result = try await webView.callAsyncJavaScript(
                "return await window.mornDesktopTube.togglePlayback()", arguments: [:], in: nil, contentWorld: .page)
            updatePlayback(result)
        } catch { status = "再生を操作できません。YouTube画面を開いて確認してください。" }
    }

    func refreshPlayback() async {
        let current = settingsRevision
        guard let value = try? await webView.evaluateJavaScript("window.mornDesktopTube?.state() ?? null") else {
            hasVideo = false
            return
        }
        guard current == settingsRevision else { return }
        updatePlayback(value)
    }

    private func configurePlayer() {
        settingsRevision += 1
        let current = settingsRevision
        guard webView.url != nil else { return }
        let script = "window.mornDesktopTube?.configure({volume: \(volume / 100), background: \(isWallpaper)}) ?? null"
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self, current == self.settingsRevision else { return }
            self.updatePlayback(result)
        }
    }

    private func updatePlayback(_ value: Any?) {
        guard let state = value as? [String: Any], let hasVideo = state["hasVideo"] as? Bool,
              let paused = state["paused"] as? Bool, let level = state["volume"] as? Double,
              level.isFinite else { hasVideo = false; return }
        self.hasVideo = hasVideo
        isPaused = paused
    }

    private func attach(to container: NSView) {
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }

    private var targetScreen: NSScreen? {
        screens.first { Self.displayID($0) == screenID } ?? screens.first
    }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    @objc private func displaysChanged() {
        screens = NSScreen.screens
        if !screens.contains(where: { Self.displayID($0) == screenID }) { screenID = 0 }
        moveWallpaper()
    }

    private func moveWallpaper() {
        if let screen = targetScreen { wallpaper?.setFrame(screen.frame, display: true) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, Self.isSecureNavigation(url) else {
            status = "https以外のページは開けません。"
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        hasVideo = false
        status = "読み込み中…"
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        configurePlayer()
        status = isWallpaper ? "背景に表示中" : "YouTube画面から動画を選べます。"
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { status = "読み込めませんでした: \(error.localizedDescription)" }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        status = "読み込めませんでした: \(error.localizedDescription)"
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        hasVideo = false
        status = "再生プロセスが終了しました。YouTube画面で再読み込みしてください。"
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, Self.isSecureNavigation(url) { webView.load(navigationAction.request) }
        return nil
    }
}
