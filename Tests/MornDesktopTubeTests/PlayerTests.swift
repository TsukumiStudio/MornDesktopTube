import XCTest
import SwiftUI
import WebKit
@testable import MornDesktopTube

final class PlayerTests: XCTestCase {
    @MainActor
    func testInternalPlaybackVolumeBackgroundAndStop() async throws {
        _ = NSApplication.shared
        XCTAssertTrue(PlayerController().webView.configuration.websiteDataStore.isPersistent)
        let controller = PlayerController(dataStore: .nonPersistent())
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
        XCTAssertGreaterThan(wallpaper.level.rawValue, Int(CGWindowLevelForKey(.desktopWindow)))
        XCTAssertLessThan(wallpaper.level.rawValue, Int(CGWindowLevelForKey(.desktopIconWindow)))
        XCTAssertTrue(wallpaper.collectionBehavior.contains(.canJoinAllSpaces))
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
        let host = NSHostingView(rootView: DashboardView(controller: PlayerController(dataStore: .nonPersistent()))
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
