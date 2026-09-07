import XCTest
import SwiftUI
import WebKit
@testable import MornDesktopTube

final class PlayerTests: XCTestCase {
    @MainActor
    func testLastVideoRestoresWithoutDashboard() async throws {
        _ = NSApplication.shared
        let suite = "MornDesktopTube.restore-test.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let fixture = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "blue", withExtension: "mp4", subdirectory: "Fixtures")))
        let html = """
            <div id="movie_player"><video muted playsinline loop src="data:video/mp4;base64,\(fixture.base64EncodedString())"></video></div>
            <script>window.videoID = 'remember001'; document.querySelector('#movie_player').getVideoData = () => ({video_id: window.videoID});</script>
            """
        var original: PlayerController? = PlayerController(dataStore: .nonPersistent(), preferences: preferences)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = original?.browserContainer
        window.orderBack(nil)
        defer { window.close() }
        original?.setVolume(0)
        original?.webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com/watch?v=remember001"))
        for _ in 0..<100 {
            if (try? await original?.webView.evaluateJavaScript("document.querySelector('video').readyState >= 2")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNil(preferences.string(forKey: "lastVideoID"), "Merely opening a video must not replace the last played video")
        _ = try await original?.webView.evaluateJavaScript("document.querySelector('video').play(); true")
        for _ in 0..<100 {
            if preferences.string(forKey: "lastVideoID") == "remember001" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(preferences.string(forKey: "lastVideoID"), "remember001", "Playback events must save without dashboard polling")
        _ = try await original?.webView.evaluateJavaScript("""
            document.querySelector('#movie_player').classList.add('ad-showing'); window.videoID = 'advert00001';
            document.querySelector('video').dispatchEvent(new Event('timeupdate'));
            """)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(preferences.string(forKey: "lastVideoID"), "remember001", "Ads must not overwrite the saved video")
        await original?.stop()
        original = nil
        window.contentView = nil

        let restored = PlayerController(dataStore: .nonPersistent(), preferences: preferences)
        restored.setVolume(0)
        defer { restored.wallpaper?.close() }
        let capture = StartupNavigationCapture()
        restored.webView.navigationDelegate = capture
        for _ in 0..<100 {
            if capture.url != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(capture.url?.absoluteString, "https://www.youtube.com/watch?v=remember001", "Startup must load the saved video, not the homepage")
        restored.webView.navigationDelegate = restored
        restored.webView.loadHTMLString(html, baseURL: capture.url ?? URL(string: "https://www.youtube.com/"))
        for _ in 0..<100 {
            if restored.isWallpaper && !restored.isPaused && restored.currentTime > 0.1 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(restored.isWallpaper, "Restored video must appear behind the desktop")
        XCTAssertFalse(restored.isPaused)
        XCTAssertGreaterThan(restored.currentTime, 0.1, "Restored playback must actually advance")
        await restored.stop()
        preferences.set("https://example.com/", forKey: "lastVideoID")
        let invalid = PlayerController(dataStore: .nonPersistent(), preferences: preferences)
        XCTAssertNil(invalid.webView.url, "Invalid stored IDs must not trigger navigation")
    }

    @MainActor
    func testRepeatPlaybackAndPersistence() async throws {
        _ = NSApplication.shared
        let suite = "MornDesktopTube.repeat-test.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        var original: PlayerController? = PlayerController(dataStore: .nonPersistent(), preferences: preferences)
        XCTAssertFalse(try XCTUnwrap(original).isRepeating)
        original?.setRepeating(true)
        original = nil
        let controller = PlayerController(dataStore: .nonPersistent(), preferences: preferences)
        XCTAssertTrue(controller.isRepeating, "Repeat must survive controller recreation")
        controller.setVolume(0)
        let webView = controller.webView
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = controller.browserContainer
        window.orderBack(nil)
        defer { window.close() }
        let fixture = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "blue", withExtension: "mp4", subdirectory: "Fixtures")))
        webView.loadHTMLString("""
            <div id="movie_player"><video muted playsinline src="data:video/mp4;base64,\(fixture.base64EncodedString())"></video></div>
            <script>window.live = false; document.querySelector('#movie_player').getVideoData = () =>
                ({video_id: 'current0001', title: 'Repeat test', isLive: window.live});</script>
            """, baseURL: URL(string: "https://www.youtube.com/"))
        for _ in 0..<100 {
            if (try? await webView.evaluateJavaScript("document.querySelector('video').readyState >= 2 && document.querySelector('video').loop")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        func flag(_ expression: String) async throws -> Bool {
            try await webView.evaluateJavaScript(expression) as? Bool == true
        }
        let initialLoop = try await flag("document.querySelector('video').loop")
        XCTAssertTrue(initialLoop)
        // Observe real end-to-start playback, without DashboardView or refreshPlayback polling.
        for _ in 0..<2 {
            _ = try await webView.callAsyncJavaScript("""
                const v = document.querySelector('video');
                v.currentTime = v.duration - 0.1;
                await v.play();
                """, arguments: [:], in: nil, contentWorld: .page)
            try await Task.sleep(for: .milliseconds(600))
            let repeated = try await flag("!document.querySelector('video').paused && document.querySelector('video').currentTime < 1")
            XCTAssertTrue(repeated, "Playback must actually return to the beginning")
        }
        _ = try await webView.evaluateJavaScript("document.querySelector('#movie_player').classList.add('ad-showing')")
        let adLoops = try await flag("document.querySelector('video').loop")
        XCTAssertFalse(adLoops, "Ads must not repeat")
        _ = try await webView.evaluateJavaScript("document.querySelector('#movie_player').classList.remove('ad-showing')")
        let restored = try await flag("document.querySelector('video').loop")
        XCTAssertTrue(restored)
        _ = try await webView.evaluateJavaScript("window.live = true; document.querySelector('video').dispatchEvent(new Event('durationchange'))")
        let liveLoops = try await flag("document.querySelector('video').loop")
        XCTAssertFalse(liveLoops)
        _ = try await webView.evaluateJavaScript("window.live = false; document.querySelector('video').dispatchEvent(new Event('durationchange'))")
        await controller.stop()
        let paused = try await flag("document.querySelector('video').paused")
        XCTAssertTrue(paused, "Repeat must not restart a stopped video")
        controller.setRepeating(false)
        _ = try await webView.callAsyncJavaScript("""
            const v = document.querySelector('video'); v.currentTime = v.duration - 0.1; await v.play();
            """, arguments: [:], in: nil, contentWorld: .page)
        try await Task.sleep(for: .milliseconds(600))
        let ended = try await flag("document.querySelector('video').ended")
        XCTAssertTrue(ended, "Turning repeat off must restore normal playback completion")
        preferences.removeObject(forKey: "lastVideoID")
        XCTAssertFalse(PlayerController(dataStore: .nonPersistent(), preferences: preferences).isRepeating)
        controller.setRepeating(true)
        _ = try await webView.evaluateJavaScript("""
            const old = document.querySelector('video'); const replacement = old.cloneNode(true);
            replacement.removeAttribute('loop'); old.replaceWith(replacement);
            """)
        for _ in 0..<100 {
            if try await flag("document.querySelector('video').loop") { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let replacementLoops = try await flag("document.querySelector('video').loop")
        XCTAssertTrue(replacementLoops, "Replacement videos must inherit repeat without dashboard polling")
    }

    @MainActor
    func testDashboardSizeIsStableAcrossUpdateStates() {
        _ = NSApplication.shared
        let suite = "MornDesktopTube.dashboard-test.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let controller = PlayerController(dataStore: .nonPersistent(), preferences: preferences)
        let states: [Updater.State] = [.idle, .checking, .upToDate, .available("v999.999.999"),
            .updating, .updated, .failed("更新を確認できませんでした。通信状態を確認してください。"), .idle]
        var initial: NSSize?
        for state in states {
            let host = NSHostingView(rootView: DashboardView(controller: controller, updater: Updater(state: state)))
            host.setFrameSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            if let initial {
                XCTAssertEqual(host.frame.width, initial.width, accuracy: 0.1, "\(state)")
                XCTAssertEqual(host.frame.height, initial.height, accuracy: 0.1, "更新状態でダッシュボードが伸縮: \(state)")
            } else { initial = host.frame.size }
        }
    }

    @MainActor
    func testInternalPlaybackVolumeBackgroundAndStop() async throws {
        _ = NSApplication.shared
        let suite = "MornDesktopTube.playback-test.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        XCTAssertTrue(PlayerController(preferences: preferences).webView.configuration.websiteDataStore.isPersistent)
        let controller = PlayerController(dataStore: .nonPersistent(), preferences: preferences)
        let webView = controller.webView
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = controller.browserContainer
        window.orderBack(nil)
        defer { window.close(); controller.wallpaper?.close() }
        let fixture = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "blue", withExtension: "mp4", subdirectory: "Fixtures")))
        webView.loadHTMLString("""
            <html><body><nav id="navigation">YouTube navigation</nav>
            <div id="movie_player"><video id="video" loop playsinline src="data:video/mp4;base64,\(fixture.base64EncodedString())"></video></div>
            <a class="ytp-next-button" aria-disabled="false" href="https://www.youtube.com/watch?v=next0000001"
               data-tooltip-text="次のテスト曲" onclick="event.preventDefault(); window.nextCount = (window.nextCount || 0) + 1">Next</a>
            <a class="ytp-prev-button" aria-disabled="false" onclick="window.previousCount = (window.previousCount || 0) + 1">Previous</a>
            <script>document.querySelector('#movie_player').getVideoData = () => ({video_id: 'current0001', title: '再生中のテスト曲', isLive: false});</script>
            </body></html>
            """, baseURL: URL(string: "https://www.youtube.com/"))
        for _ in 0..<100 {
            if (try? await webView.evaluateJavaScript("!!window.mornDesktopTube && document.querySelector('video').readyState >= 2")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        await controller.refreshPlayback()
        XCTAssertTrue(controller.hasVideo, "The local MP4 did not load; inspect WebKit navigation and script injection")
        await controller.togglePlayback()
        XCTAssertFalse(controller.isPaused)
        let before = try await webView.evaluateJavaScript("document.querySelector('video').currentTime") as! Double
        try await Task.sleep(for: .milliseconds(150))
        let after = try await webView.evaluateJavaScript("document.querySelector('video').currentTime") as! Double
        XCTAssertGreaterThan(after, before, "Playback time must advance")

        controller.setVolume(90)
        controller.setVolume(37)
        let level = try await webView.evaluateJavaScript("document.querySelector('video').volume") as! Double
        XCTAssertEqual(level, 0.37, accuracy: 0.001)
        XCTAssertEqual(controller.volume, 37, accuracy: 0.01)
        controller.setVolume(.nan)
        XCTAssertEqual(controller.volume, 37, accuracy: 0.01)
        _ = try await webView.evaluateJavaScript("document.querySelector('video').volume = 1")
        try await Task.sleep(for: .milliseconds(30))
        let restoredVolume = try await webView.evaluateJavaScript("document.querySelector('video').volume") as! Double
        XCTAssertEqual(restoredVolume, 0.37, accuracy: 0.001, "YouTube's own volume restoration must not override the dashboard")

        await controller.refreshPlayback()
        XCTAssertEqual(controller.currentTrack?.title, "再生中のテスト曲")
        XCTAssertEqual(controller.currentTrack?.thumbnailURL.absoluteString, "https://i.ytimg.com/vi/current0001/mqdefault.jpg")
        XCTAssertEqual(controller.nextTrack?.title, "次のテスト曲")
        XCTAssertEqual(controller.nextTrack?.thumbnailURL.absoluteString, "https://i.ytimg.com/vi/next0000001/mqdefault.jpg")
        XCTAssertTrue(controller.canNext)
        XCTAssertTrue(controller.canPrevious)
        await controller.next()
        await controller.previous()
        let nextCount = try await webView.evaluateJavaScript("window.nextCount") as? Int
        let previousCount = try await webView.evaluateJavaScript("window.previousCount") as? Int
        XCTAssertEqual(nextCount, 1)
        XCTAssertEqual(previousCount, 1)
        await controller.togglePlayback()
        await controller.seek(to: 1.25, videoID: "current0001")
        let sought = try await webView.evaluateJavaScript("document.querySelector('video').currentTime") as! Double
        XCTAssertEqual(sought, 1.25, accuracy: 0.05)
        await controller.seek(to: 0.5, videoID: "different01")
        await controller.seek(to: .nan, videoID: "current0001")
        let unchanged = try await webView.evaluateJavaScript("document.querySelector('video').currentTime") as! Double
        XCTAssertEqual(unchanged, sought, accuracy: 0.05)
        _ = try await webView.evaluateJavaScript("document.querySelector('#movie_player').classList.add('ad-showing')")
        await controller.refreshPlayback()
        XCTAssertFalse(controller.canSeek)
        XCTAssertFalse(controller.canNext)
        XCTAssertFalse(controller.canPrevious)
        _ = try await webView.evaluateJavaScript("document.querySelector('#movie_player').classList.remove('ad-showing'); document.querySelector('.ytp-next-button').setAttribute('aria-disabled', 'true')")
        await controller.refreshPlayback()
        XCTAssertNil(controller.nextTrack)
        XCTAssertFalse(controller.canNext)
        await controller.togglePlayback()

        await controller.showWallpaper()
        let wallpaper = try XCTUnwrap(controller.wallpaper)
        XCTAssertTrue(controller.isWallpaper)
        XCTAssertTrue(controller.webView === webView)
        XCTAssertTrue(webView.superview === wallpaper.contentView)
        XCTAssertEqual(wallpaper.frame, screen.frame)
        XCTAssertTrue(wallpaper.ignoresMouseEvents)
        XCTAssertFalse(wallpaper.canBecomeKey)
        XCTAssertEqual(wallpaper.level.rawValue, Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        XCTAssertLessThan(wallpaper.level.rawValue, Int(CGWindowLevelForKey(.desktopIconWindow)))
        XCTAssertTrue(wallpaper.collectionBehavior.contains(.canJoinAllSpaces))
        try await Task.sleep(for: .milliseconds(100))
        let orderedWindows = try XCTUnwrap(CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]])
        let wallpaperIndex = try XCTUnwrap(orderedWindows.firstIndex {
            ($0[kCGWindowNumber as String] as? Int) == wallpaper.windowNumber
        }, "Wallpaper must actually be on screen")
        let desktopIcons = orderedWindows.indices.filter {
            (orderedWindows[$0][kCGWindowOwnerName as String] as? String) == "Finder" &&
            (orderedWindows[$0][kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.desktopIconWindow))
        }
        if desktopIcons.isEmpty { XCTFail("No Finder desktop icon window found; run with a visible macOS desktop") }
        for index in desktopIcons {
            XCTAssertLessThan(index, wallpaperIndex, "Finder icons must be in front of the actual wallpaper window")
        }
        let hidden = try await webView.evaluateJavaScript("getComputedStyle(document.querySelector('nav')).visibility") as? String
        XCTAssertEqual(hidden, "hidden")
        let fit = try await webView.evaluateJavaScript("getComputedStyle(document.querySelector('video')).objectFit") as? String
        XCTAssertEqual(fit, "contain")
        await controller.stop()
        XCTAssertFalse(controller.isWallpaper)
        XCTAssertTrue(webView.superview === controller.browserContainer)
        let stoppedAt = try await webView.evaluateJavaScript("document.querySelector('video').currentTime") as! Double
        try await Task.sleep(for: .milliseconds(150))
        let stillAt = try await webView.evaluateJavaScript("document.querySelector('video').currentTime") as! Double
        XCTAssertEqual(stoppedAt, stillAt, accuracy: 0.01, "Stop must pause actual playback")
        let visible = try await webView.evaluateJavaScript("getComputedStyle(document.querySelector('nav')).visibility") as? String
        XCTAssertEqual(visible, "visible")
        let replacement = try await webView.evaluateJavaScript("""
            document.querySelector('video').remove();
            document.querySelector('#movie_player').appendChild(document.createElement('video'));
            window.mornDesktopTube.state();
            """) as? [String: Any]
        XCTAssertEqual(replacement?["hasVideo"] as? Bool, false, "An empty home-page player is not a playable video")
        XCTAssertEqual(replacement?["volume"] as? Double, 0.37, "New player elements must inherit this app's volume")
    }

    @MainActor
    func testURLValidationAndDashboard() throws {
        _ = NSApplication.shared
        XCTAssertEqual(PlayerController.youtubeURL(" youtu.be/example ")?.absoluteString, "https://youtu.be/example")
        for input in ["", "https://youtube.com.evil.example/watch", "https://user@youtube.com/", "http://youtube.com/", "file:///tmp/video", "javascript:alert(1)"] {
            XCTAssertNil(PlayerController.youtubeURL(input), input)
        }
        XCTAssertTrue(PlayerController.isSecureNavigation(URL(string: "https://accounts.google.com/")!))
        XCTAssertFalse(PlayerController.isSecureNavigation(URL(string: "file:///etc/passwd")!))
        XCTAssertNil(VideoTrack(["id": "../secret"]))
        XCTAssertEqual(DashboardView.timeLabel(3661), "1:01:01")
        XCTAssertEqual(DashboardView.timeLabel(.infinity), "--:--")
        XCTAssertEqual(DashboardView.timeLabel(nil), "--:--")
        let suite = "MornDesktopTube.url-test.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let host = NSHostingView(rootView: DashboardView(controller: PlayerController(dataStore: .nonPersistent(), preferences: preferences))
            .background(Color(nsColor: .windowBackgroundColor)))
        host.setFrameSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.frame.width, 360, accuracy: 1)
        XCTAssertLessThan(host.frame.height, 640)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/dashboard-preview.png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output)
    }
}

@MainActor
private final class StartupNavigationCapture: NSObject, WKNavigationDelegate {
    var url: URL?
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        url = navigationAction.request.url
        decisionHandler(.cancel)
    }
}
