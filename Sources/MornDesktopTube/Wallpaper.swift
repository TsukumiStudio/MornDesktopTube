import AppKit
import AVFoundation

final class VideoView: NSView {
    let videoLayer = AVSampleBufferDisplayLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(videoLayer)
        videoLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }

    func display(_ sample: CMSampleBuffer) {
        let renderer = videoLayer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        guard renderer.isReadyForMoreMediaData else { return }
        // Capture timestamps use the host clock; present immediately without an audio clock.
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true)
            as? [NSMutableDictionary]
        attachments?.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        renderer.enqueue(sample)
    }
}

final class WallpaperWindow: NSWindow {
    let videoView: VideoView

    init(screen: NSScreen) {
        videoView = VideoView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: .borderless,
                   backing: .buffered, defer: false)
        contentView = videoView
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hasShadow = false
        isOpaque = true
        backgroundColor = .black
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        title = "MornDesktopTube 背景"
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
