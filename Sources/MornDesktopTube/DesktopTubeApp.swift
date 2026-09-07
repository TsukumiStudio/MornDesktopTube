import SwiftUI

enum Spacing {
    static let edge: CGFloat = 24
    static let panel: CGFloat = 16
    static let gap: CGFloat = 8
    static let section: CGFloat = 20
}

@main
struct DesktopTubeApp: App {
    @StateObject private var controller = PlayerController()
    @StateObject private var updater = Updater()
    var body: some Scene {
        MenuBarExtra("MornDesktopTube", systemImage: "play.rectangle.on.rectangle") {
            DashboardView(controller: controller, updater: updater)
        }
        .menuBarExtraStyle(.window)
    }
}

struct DashboardView: View {
    @ObservedObject var controller: PlayerController
    @ObservedObject var updater: Updater = Updater()
    @State private var scrubbing = false
    @State private var seekPosition = 0.0
    @State private var seekVideoID: String?
    @Environment(\.dismiss) private var dismiss

    static func timeLabel(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "--:--" }
        let total = Int(seconds)
        let minutes = String(format: "%02d", (total / 60) % 60)
        let remainder = String(format: "%02d", total % 60)
        return total >= 3600 ? "\(total / 3600):\(minutes):\(remainder)" : "\(total / 60):\(remainder)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.panel) {
            HStack {
                Button("ブラウザを開く") { dismiss(); controller.showBrowser() }
                Spacer()
                Button(controller.isWallpaper ? "背景を中止" : "背景に表示") {
                    Task {
                        if controller.isWallpaper { await controller.stop() }
                        else { await controller.showWallpaper(); dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.isWallpaper ? Color.red : Color.accentColor)
                .disabled(!controller.hasVideo && !controller.isWallpaper)
            }
            Label("MornDesktopTube", systemImage: "play.rectangle.on.rectangle").font(.headline)
            HStack(spacing: Spacing.gap) {
                TrackArtwork(track: controller.currentTrack, width: Spacing.panel * 7)
                VStack(alignment: .leading, spacing: Spacing.gap) {
                    Text(controller.currentTrack.map { $0.title.isEmpty ? "タイトルを取得できません" : $0.title } ?? "動画を再生してください")
                        .font(.headline).lineLimit(2)
                    Text(controller.hasVideo ? (controller.isPaused ? "一時停止中" : "再生中") : "未再生")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: Spacing.gap) {
                Slider(value: Binding(
                    get: { min(scrubbing ? seekPosition : controller.currentTime, controller.duration ?? 1) },
                    set: { value in
                        if !scrubbing { Task { await controller.seek(to: value, videoID: controller.currentTrack?.id) } }
                        seekPosition = value
                    }
                ), in: 0...max(controller.duration ?? 1, 1), onEditingChanged: { editing in
                    if editing {
                        seekPosition = controller.currentTime
                        seekVideoID = controller.currentTrack?.id
                    } else {
                        let position = seekPosition
                        let id = seekVideoID
                        Task { await controller.seek(to: position, videoID: id) }
                    }
                    scrubbing = editing
                })
                .disabled(!controller.canSeek || controller.isControlling)
                .accessibilityLabel("再生位置")
                HStack {
                    Text(Self.timeLabel(scrubbing ? seekPosition : controller.currentTime))
                    Spacer()
                    Text(controller.isLive ? "ライブ" : Self.timeLabel(controller.duration))
                }.font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            HStack(spacing: Spacing.panel) {
                Spacer()
                transport("backward.end.fill", "前の動画", enabled: controller.canPrevious) { await controller.previous() }
                transport(controller.isPaused ? "play.fill" : "pause.fill", controller.isPaused ? "再生" : "一時停止",
                          enabled: controller.hasVideo) { await controller.togglePlayback() }
                transport("forward.end.fill", "次の動画", enabled: controller.canNext) { await controller.next() }
                let repeatButton = Button { controller.setRepeating(!controller.isRepeating) } label: {
                    Image(systemName: "repeat").frame(width: Spacing.panel, height: Spacing.panel)
                        .overlay(alignment: .topTrailing) {
                            if controller.isRepeating {
                                Image(systemName: "checkmark")
                                    .font(.system(size: Spacing.gap, weight: .bold))
                                    .offset(x: Spacing.gap, y: -Spacing.gap / 2)
                            }
                        }
                }
                Group {
                    if controller.isRepeating {
                        repeatButton.buttonStyle(.borderedProminent).tint(.accentColor).foregroundStyle(.white)
                    } else {
                        repeatButton
                    }
                }
                .accessibilityLabel("この動画をリピート")
                .accessibilityValue(controller.isRepeating ? "オン" : "オフ")
                .help(controller.isRepeating ? "リピート：オン（クリックでオフ）" : "リピート：オフ（クリックでオン）")
                Spacer()
            }
            HStack(spacing: Spacing.gap) {
                TrackArtwork(track: controller.nextTrack, width: Spacing.panel * 5)
                VStack(alignment: .leading, spacing: Spacing.gap) {
                    Text("次の動画").font(.caption).foregroundStyle(.secondary)
                    Text(controller.nextTrack.map { $0.title.isEmpty ? "タイトルを取得できません" : $0.title } ?? "次の動画の情報はありません")
                        .font(.callout).lineLimit(2)
                }
            }
            Divider()
            HStack(spacing: Spacing.gap) {
                Image(systemName: controller.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                Slider(value: Binding(get: { controller.volume }, set: { controller.setVolume($0) }), in: 0...100, step: 1)
                    .accessibilityLabel("動画の音量")
                Text("\(Int(controller.volume))%").font(.caption).monospacedDigit().frame(width: Spacing.panel * 2.5)
            }
            Picker("表示先", selection: $controller.screenID) {
                Text("メインディスプレイ").tag(CGDirectDisplayID(0))
                ForEach(controller.screens, id: \.self) { screen in
                    Text(screen.localizedName).tag(PlayerController.displayID(screen))
                }
            }
            HStack {
                updateControls
                Spacer()
                Text("ver \(Updater.version)").font(.caption).foregroundStyle(.secondary)
            }
            .frame(height: Spacing.panel * 2)
        }
        .padding(Spacing.edge).frame(width: 360)
        .task {
            while !Task.isCancelled {
                if !scrubbing { await controller.refreshPlayback() }
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { return }
            }
        }
    }

    @ViewBuilder private var updateControls: some View {
        switch updater.state {
        case .idle:
            Button("更新を確認") { Task { await updater.check() } }
        case .checking:
            Text("更新を確認中…").font(.caption)
        case .available(let tag):
            Button("最新へ更新") { Task { await updater.update() } }.help(tag)
        case .upToDate:
            Button("最新版です ↻") { Task { await updater.check() } }.help("更新を確認")
        case .updating:
            Text("更新中…").font(.caption)
        case .updated:
            Button("再起動して適用") { updater.restart() }
        case .failed(let message):
            Button("確認失敗・再試行") { Task { await updater.check() } }
                .foregroundStyle(.red).help(message).accessibilityHint(message)
        }
    }

    private func transport(_ image: String, _ label: String, enabled: Bool, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: image).frame(width: Spacing.panel, height: Spacing.panel)
        }
        .disabled(!enabled || controller.isControlling).help(label).accessibilityLabel(label)
    }
}

private struct TrackArtwork: View {
    let track: VideoTrack?
    let width: CGFloat
    var body: some View {
        AsyncImage(url: track?.thumbnailURL) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: width, height: width * 9 / 16)
        .clipped().clipShape(RoundedRectangle(cornerRadius: Spacing.gap)).accessibilityHidden(true)
    }
}
