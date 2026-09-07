import AppKit
import Combine
import ScreenCaptureKit

@MainActor
final class MirrorController: NSObject, ObservableObject, SCContentSharingPickerObserver,
                              SCStreamOutput, SCStreamDelegate {
    @Published private(set) var isRunning = false
    @Published private(set) var isBusy = false
    @Published private(set) var status = "YouTubeをブラウザで再生して、ウィンドウを選んでください。"
    @Published var fillScreen = false {
        didSet { wallpaper?.videoView.videoLayer.videoGravity = fillScreen ? .resizeAspectFill : .resizeAspect }
    }
    @Published var screenID: CGDirectDisplayID = 0 { didSet { moveWallpaper() } }
    @Published private(set) var screens = NSScreen.screens
    private var stream: SCStream?
    private var wallpaper: WallpaperWindow?
    private var generation = 0
    private var receivedFrame = false
    private var timeout: Task<Void, Never>?
    private let picker = SCContentSharingPicker.shared

    override init() {
        super.init()
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow]
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "studio.tsukumi.MornDesktopTube"]
        picker.defaultConfiguration = configuration
        picker.maximumStreamCount = 1
        picker.add(self)
        picker.isActive = true
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func chooseWindow() {
        if let stream { picker.present(for: stream, using: .window) }
        else { picker.present(using: .window) }
    }

    func stop() async {
        generation += 1
        let current = generation
        timeout?.cancel()
        let oldStream = stream
        stream = nil
        wallpaper?.close()
        wallpaper = nil
        isRunning = false
        isBusy = false
        status = "背景表示を停止しました。ブラウザの再生は続きます。"
        do { try await oldStream?.stopCapture() }
        catch {
            if current == generation {
                status = "背景は閉じましたが、収録の停止に失敗しました: \(error.localizedDescription)"
            }
        }
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

    private func start(filter: SCContentFilter) async {
        let current = generation + 1
        await stop()
        guard current == generation else { return }
        guard let screen = targetScreen else {
            status = "表示先の画面がありません。ディスプレイを接続してください。"
            return
        }
        isBusy = true
        status = "映像を待っています…"
        receivedFrame = false
        let window = WallpaperWindow(screen: screen)
        window.videoView.videoLayer.videoGravity = fillScreen ? .resizeAspectFill : .resizeAspect
        wallpaper = window

        let configuration = SCStreamConfiguration()
        // ponytail: at most 1080p / 30 fps; raise this ceiling if sharper wallpaper is needed.
        let size = filter.contentRect.size
        let scale = min(1920 / max(size.width, 1), 1080 / max(size.height, 1), CGFloat(filter.pointPixelScale))
        configuration.width = max(2, Int(size.width * scale) / 2 * 2)
        configuration.height = max(2, Int(size.height * scale) / 2 * 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        stream = newStream
        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
            try await newStream.startCapture()
            guard current == generation, stream === newStream else {
                try? await newStream.stopCapture()
                return
            }
            isBusy = false
            isRunning = true
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self, self.stream === newStream, !self.receivedFrame else { return }
                self.status = "映像が届きません。元のウィンドウを表示し、最小化を解除してください。"
            }
        } catch {
            guard current == generation else { return }
            stream = nil
            wallpaper?.close()
            wallpaper = nil
            isBusy = false
            status = "開始できませんでした: \(error.localizedDescription)"
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in await start(filter: filter) }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {}

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in status = "ウィンドウを選択できませんでした: \(error.localizedDescription)" }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.stream === stream else { return }
            await stop()
            status = "背景表示が終了しました。ウィンドウを選び直してください: \(error.localizedDescription)"
        }
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        // ScreenCaptureKit delivers this output on .main (registered above).
        MainActor.assumeIsolated {
            guard self.stream === stream, type == .screen, sampleBuffer.isValid,
                  let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                      as? [[SCStreamFrameInfo: Any]],
                  let status = attachments.first?[.status] as? Int,
                  status == SCFrameStatus.complete.rawValue else { return }
            wallpaper?.videoView.display(sampleBuffer)
            if !receivedFrame {
                receivedFrame = true
                wallpaper?.orderBack(nil)
                self.status = "背景を表示中 · 音量・再生操作はブラウザで行えます。"
            }
        }
    }
}
