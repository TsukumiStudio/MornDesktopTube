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
    var body: some Scene {
        MenuBarExtra("MornDesktopTube", systemImage: "play.rectangle.on.rectangle") {
            DashboardView(controller: controller)
        }
        .menuBarExtraStyle(.window)
    }
}

struct DashboardView: View {
    @ObservedObject var controller: PlayerController
    @State private var videoURL = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            VStack(alignment: .leading, spacing: Spacing.gap) {
                Label("MornDesktopTube", systemImage: "play.rectangle.on.rectangle").font(.headline)
                Text(controller.status).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Spacing.gap) {
                TextField("YouTube URL", text: $videoURL).textFieldStyle(.roundedBorder)
                    .onSubmit { openVideo() }
                Button("開く") { openVideo() }.disabled(videoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack(spacing: Spacing.gap) {
                Button("YouTube画面") { dismiss(); controller.showBrowser() }
                Spacer()
                Button("背景に表示") { Task { await controller.showWallpaper(); dismiss() } }
                    .buttonStyle(.borderedProminent).disabled(!controller.hasVideo || controller.isWallpaper)
            }
            Divider()
            VStack(alignment: .leading, spacing: Spacing.gap) {
                HStack {
                    Label("動画の音量", systemImage: controller.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    Spacer()
                    Text("\(Int(controller.volume))%").foregroundStyle(.secondary).monospacedDigit()
                }
                Slider(value: Binding(get: { controller.volume }, set: { controller.setVolume($0) }), in: 0...100, step: 1)
                    .accessibilityLabel("動画の音量")
                HStack {
                    Button(controller.isPaused ? "再生" : "一時停止") { Task { await controller.togglePlayback() } }
                        .disabled(!controller.hasVideo)
                    Spacer()
                    Button("背景と再生を停止") { Task { await controller.stop() } }
                        .disabled(!controller.hasVideo && !controller.isWallpaper)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: Spacing.panel) {
                Picker("表示先", selection: $controller.screenID) {
                    Text("メインディスプレイ").tag(CGDirectDisplayID(0))
                    ForEach(controller.screens, id: \.self) { screen in
                        Text(screen.localizedName).tag(PlayerController.displayID(screen))
                    }
                }
            }
            Text("ログイン情報はアプリ専用に保持します。Google側の制限でログインできない場合があります。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("外部ブラウザ・画面収録は不要").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("終了") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
        }
        .padding(Spacing.edge).frame(width: 360)
        .task {
            while !Task.isCancelled {
                await controller.refreshPlayback()
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
            }
        }
    }

    private func openVideo() {
        controller.openYouTube(videoURL)
        if PlayerController.youtubeURL(videoURL) != nil { dismiss() }
    }
}
