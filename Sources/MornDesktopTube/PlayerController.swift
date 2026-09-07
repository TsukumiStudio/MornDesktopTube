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
    @Published private(set) var isRepeating: Bool
    private let preferences: UserDefaults
    @Published private(set) var currentTrack: VideoTrack?
    @Published private(set) var nextTrack: VideoTrack?
    @Published private(set) var currentTime = 0.0
    @Published private(set) var duration: Double?
    @Published private(set) var canSeek = false
    @Published private(set) var canNext = false
    @Published private(set) var canPrevious = false
    @Published private(set) var isLive = false
    @Published private(set) var isControlling = false
    private var playerCanPrevious = false
    @Published var screenID: CGDirectDisplayID = 0 { didSet { moveWallpaper() } }
    @Published private(set) var screens = NSScreen.screens
    let webView: WKWebView
    let browserContainer = NSView()
    private(set) var wallpaper: WallpaperWindow?
    private var browserWindow: NSWindow?
    private var addressObservation: NSKeyValueObservation?
    private var settingsRevision = 0
    private var presentationRevision = 0
    private var restoringVideoID: String?

    init(dataStore: WKWebsiteDataStore? = nil, preferences: UserDefaults = .standard) {
        self.preferences = preferences
        isRepeating = preferences.bool(forKey: "repeatVideo")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore ?? .default()
        configuration.applicationNameForUserAgent = "MornDesktopTube/0.2"
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.userContentController.addUserScript(WKUserScript(
            source: PlayerScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        let messages = PlaybackMessages()
        messages.controller = self
        configuration.userContentController.add(messages, name: "playback")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        attach(to: browserContainer)
        addressObservation = webView.observe(\.url, options: [.new]) { [weak self] view, _ in
            Task { @MainActor in self?.pageAddress = view.url?.absoluteString ?? "" }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if let track = VideoTrack(["id": preferences.string(forKey: "lastVideoID") ?? ""]) {
            restoringVideoID = track.id
            presentWallpaper()
            webView.load(URLRequest(url: URL(string: "https://www.youtube.com/watch?v=\(track.id)")!))
        }
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

    func showBrowser() {
        restoringVideoID = nil
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
        guard hasVideo else {
            status = "アプリ内のYouTubeで動画を開いてください。"
            return
        }
        presentWallpaper()
    }

    private func presentWallpaper() {
        guard let screen = targetScreen else { return }
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
        restoringVideoID = nil
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

    func setRepeating(_ enabled: Bool) {
        isRepeating = enabled
        preferences.set(enabled, forKey: "repeatVideo")
        configurePlayer()
    }

    func togglePlayback() async {
        await performPlayerAction("return await window.mornDesktopTube.togglePlayback()")
    }

    func seek(to seconds: Double, videoID: String?) async {
        guard seconds.isFinite, canSeek, videoID == currentTrack?.id else { return }
        await performPlayerAction("return window.mornDesktopTube.seek(seconds, expectedID)",
            arguments: ["seconds": seconds, "expectedID": videoID as Any? ?? NSNull()])
    }

    func next() async {
        guard canNext else { return }
        await performPlayerAction("return window.mornDesktopTube.skip(1)")
    }

    func previous() async {
        guard canPrevious else { return }
        if playerCanPrevious {
            await performPlayerAction("return window.mornDesktopTube.skip(-1)")
        } else if let item = previousHistoryItem {
            webView.go(to: item)
        }
    }

    private var previousHistoryItem: WKBackForwardListItem? {
        webView.backForwardList.backList.reversed().first { item in
            guard Self.youtubeURL(item.url.absoluteString) != nil,
                  let id = URLComponents(url: item.url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value else { return false }
            return id != currentTrack?.id && VideoTrack(["id": id]) != nil
        }
    }

    private func performPlayerAction(_ script: String, arguments: [String: Any] = [:]) async {
        guard !isControlling else { return }
        isControlling = true
        defer { isControlling = false }
        do {
            let result = try await webView.callAsyncJavaScript(
                script, arguments: arguments, in: nil, contentWorld: .page)
            updatePlayback(result)
        } catch { status = "操作できませんでした。動画の切り替え中や、操作に対応していない場合があります。" }
    }

    func refreshPlayback() async {
        let current = settingsRevision
        guard let value = try? await webView.evaluateJavaScript("window.mornDesktopTube?.state() ?? null") else {
            clearPlayback()
            return
        }
        guard current == settingsRevision else { return }
        updatePlayback(value)
    }

    private func configurePlayer() {
        settingsRevision += 1
        let current = settingsRevision
        let settings = "{volume: \(volume / 100), background: \(isWallpaper), repeatVideo: \(isRepeating)}"
        // Carry presentation settings into the next document before its first paint.
        let scripts = webView.configuration.userContentController
        scripts.removeAllUserScripts()
        scripts.addUserScript(WKUserScript(
            source: "window.mornDesktopTubeSettings = \(settings);\n" + PlayerScript.source,
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        guard webView.url != nil else { return }
        let script = "window.mornDesktopTube?.configure(\(settings)) ?? null"
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self, current == self.settingsRevision else { return }
            self.updatePlayback(result)
        }
    }

    private func updatePlayback(_ value: Any?) {
        guard let state = value as? [String: Any], let hasVideo = state["hasVideo"] as? Bool,
              let paused = state["paused"] as? Bool, let level = state["volume"] as? Double,
              level.isFinite else { clearPlayback(); return }
        self.hasVideo = hasVideo
        isPaused = paused
        currentTrack = VideoTrack(state["currentTrack"])
        nextTrack = VideoTrack(state["nextTrack"])
        let time = state["currentTime"] as? Double ?? 0
        currentTime = time.isFinite ? max(0, time) : 0
        let length = state["duration"] as? Double
        duration = length.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        isLive = state["isLive"] as? Bool ?? false
        canSeek = hasVideo && duration != nil && (state["canSeek"] as? Bool == true)
        canNext = hasVideo && (state["canNext"] as? Bool == true)
        playerCanPrevious = state["canPrevious"] as? Bool == true
        canPrevious = hasVideo && state["adPlaying"] as? Bool != true && (playerCanPrevious || previousHistoryItem != nil)
        if hasVideo, !paused, state["adPlaying"] as? Bool == false, let track = currentTrack,
           preferences.string(forKey: "lastVideoID") != track.id {
            preferences.set(track.id, forKey: "lastVideoID")
        }
    }

    fileprivate func playbackChanged(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let url = message.frameInfo.request.url, Self.youtubeURL(url.absoluteString) != nil else { return }
        updatePlayback(message.body)
        guard hasVideo, let id = restoringVideoID, currentTrack?.id == id,
              (message.body as? [String: Any])?["adPlaying"] as? Bool == false else { return }
        restoringVideoID = nil
        let revision = presentationRevision
        Task { [weak self] in
            guard let self, revision == self.presentationRevision else { return }
            guard self.isWallpaper else { return }
            do {
                _ = try await self.webView.callAsyncJavaScript("""
                    if (window.mornDesktopTube.state().currentTrack?.id === expectedID) {
                        const v = document.querySelector('#movie_player video, video');
                        if (v?.paused) await v.play();
                    }
                    """, arguments: ["expectedID": id], in: nil, contentWorld: .page)
            } catch { self.status = "自動再生できませんでした。再生ボタンを押してください。" }
        }
    }

    private func clearPlayback() {
        hasVideo = false
        isPaused = true
        currentTrack = nil
        nextTrack = nil
        currentTime = 0
        duration = nil
        canSeek = false
        canNext = false
        canPrevious = false
        isLive = false
        playerCanPrevious = false
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
        clearPlayback()
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
        clearPlayback()
        status = "再生プロセスが終了しました。YouTube画面で再読み込みしてください。"
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, Self.isSecureNavigation(url) { webView.load(navigationAction.request) }
        return nil
    }
}

@MainActor
private final class PlaybackMessages: NSObject, WKScriptMessageHandler {
    weak var controller: PlayerController?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        controller?.playbackChanged(message)
    }
}
