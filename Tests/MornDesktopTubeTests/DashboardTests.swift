import XCTest
import SwiftUI
@testable import MornDesktopTube

final class DashboardTests: XCTestCase {
    @MainActor
    func testVolumeCommandsAndDashboardRendering() throws {
        _ = NSApplication.shared
        XCTAssertNil(SystemVolume.volumeCommand(.nan))
        XCTAssertNil(SystemVolume.volumeCommand(.infinity))
        XCTAssertEqual(SystemVolume.volumeCommand(-20), "set volume output volume 0 without output muted")
        XCTAssertEqual(SystemVolume.volumeCommand(140), "set volume output volume 100 without output muted")
        XCTAssertEqual(SystemVolume.volumeCommand(42.4), "set volume output volume 42 without output muted")
        let command = try XCTUnwrap(SystemVolume.volumeCommand(42))
        var error: NSDictionary?
        XCTAssertTrue(try XCTUnwrap(NSAppleScript(source: command)).compileAndReturnError(&error))
        XCTAssertNil(error)

        // Read-only integration: never change the user's actual output volume in tests.
        let volume = SystemVolume()
        volume.refresh()
        XCTAssertTrue(volume.available, volume.error ?? "Volume could not be read")
        XCTAssertTrue((0...100).contains(volume.level))

        let host = NSHostingView(rootView: DashboardView(controller: MirrorController())
            .background(Color(nsColor: .windowBackgroundColor)))
        host.setFrameSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.frame.width, 360, accuracy: 1)
        XCTAssertGreaterThan(host.frame.height, 300)
        XCTAssertLessThan(host.frame.height, 640)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/dashboard-preview.png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output)
    }
}
