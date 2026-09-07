import SwiftUI

private enum Spacing {
    static let edge: CGFloat = 24
    static let panel: CGFloat = 16
    static let gap: CGFloat = 8
    static let section: CGFloat = 20
}

@main
struct DesktopTubeApp: App {
    @StateObject private var controller = MirrorController()
    var body: some Scene {
        MenuBarExtra("MornDesktopTube", systemImage: "play.rectangle.on.rectangle") {
            DashboardView(controller: controller)
        }
        .menuBarExtraStyle(.window)
    }
}

struct DashboardView: View {
    @ObservedObject var controller: MirrorController
    @StateObject private var volume = SystemVolume()
    @State private var editingVolume = false
    @State private var draftVolume = 0.0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            VStack(alignment: .leading, spacing: Spacing.gap) {
                Label("MornDesktopTube", systemImage: "play.rectangle.on.rectangle")
                    .font(.headline)
                Text(controller.status)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Spacing.gap) {
                Button("ウィンドウを選ぶ") {
                    dismiss()
                    controller.chooseWindow()
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isBusy)
                Spacer()
                Button("背景を停止") { Task { await controller.stop() } }
                    .disabled(!controller.isRunning && !controller.isBusy)
            }
            Divider()
            VStack(alignment: .leading, spacing: Spacing.gap) {
                HStack {
                    Label("Mac全体の音量", systemImage: volume.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    Spacer()
                    Text(volume.available ? (volume.muted ? "消音中" : "\(Int(editingVolume ? draftVolume : volume.level))%") : "取得できません")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                Slider(value: Binding(
                    get: { editingVolume ? draftVolume : volume.level },
                    set: { draftVolume = $0; volume.setLevel($0) }
                ), in: 0...100, step: 1) { editing in
                    editingVolume = editing
                    if editing { draftVolume = volume.level }
                }
                .disabled(!volume.available)
                .accessibilityLabel("Mac全体の音量")
                Text(volume.error ?? "ほかのアプリの音量も変わります。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: Spacing.panel) {
                Picker("表示先", selection: $controller.screenID) {
                    Text("メインディスプレイ").tag(CGDirectDisplayID(0))
                    ForEach(controller.screens, id: \.self) { screen in
                        Text(screen.localizedName).tag(MirrorController.displayID(screen))
                    }
                }
                Toggle("画面いっぱいに拡大", isOn: $controller.fillScreen)
                    .help("映像の端が切れる場合があります")
            }
            Text("YouTube専用のウィンドウを開いたままにしてください。選んだウィンドウ全体が背景に映ります。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Link("YouTubeを開く", destination: URL(string: "https://www.youtube.com/")!)
                Spacer()
                Button("終了") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
        }
        .padding(Spacing.edge)
        .frame(width: 360)
        .task {
            while !Task.isCancelled {
                if !editingVolume { volume.refresh() }
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
            }
        }
    }
}
