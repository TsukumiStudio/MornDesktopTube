import XCTest
import AppKit
import AVFoundation
@testable import MornDesktopTube

final class WallpaperTests: XCTestCase {
    @MainActor
    func testDesktopPlacementAndRealFrameRendering() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first, "A macOS window server is required")
        let window = WallpaperWindow(screen: screen)
        defer { window.close() }
        XCTAssertEqual(window.frame, screen.frame)
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertGreaterThan(window.level.rawValue, Int(CGWindowLevelForKey(.desktopWindow)))
        XCTAssertLessThan(window.level.rawValue, Int(CGWindowLevelForKey(.desktopIconWindow)))
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertEqual(window.videoView.videoLayer.videoGravity, .resizeAspect)

        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 36, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(pixelBuffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels))
        memset(bytes, 0x7f, CVPixelBufferGetDataSize(pixels))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        var format: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: pixels, formatDescriptionOut: &format), noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var buffer: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: pixels, formatDescription: try XCTUnwrap(format), sampleTiming: &timing,
            sampleBufferOut: &buffer), noErr)
        let sample = try XCTUnwrap(buffer)
        window.setContentSize(NSSize(width: 64, height: 36))
        window.orderBack(nil)
        window.videoView.layoutSubtreeIfNeeded()
        window.videoView.display(sample)
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[String: Any]]
        XCTAssertEqual(attachments?.first?[kCMSampleAttachmentKey_DisplayImmediately as String] as? Bool, true)
        if #available(macOS 14.4, *) {
            let renderer = window.videoView.videoLayer.sampleBufferRenderer
            for _ in 0..<50 {
                if let displayed = renderer.displayedPixelBuffer() {
                    XCTAssertEqual(CVPixelBufferGetWidth(displayed), 64)
                    XCTAssertEqual(CVPixelBufferGetHeight(displayed), 36)
                    return
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTFail("No frame rendered within 1 second; check VideoView.display enqueue path")
        }
    }
}
