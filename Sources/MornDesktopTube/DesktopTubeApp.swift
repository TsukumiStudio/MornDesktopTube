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
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("MornDesktopTube", id: "controls") {
            VStack(alignment: .leading, spacing: Spacing.section) {
                VStack(alignment: .leading, spacing: Spacing.gap) {
                    Text("YouTubeを、デスクトップに。").font(.title2.bold())
                    Text("いつものブラウザのログイン状態で、そのまま再生。")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: Spacing.gap) {
                    Text("1. ブラウザでYouTubeを再生する")
                    Text("2. 「ウィンドウを選ぶ」で、そのウィンドウを共有する")
                    Text("3. この設定画面を閉じると、背景が見えます")
                }
                HStack(spacing: Spacing.gap) {
                    Link("YouTubeを開く", destination: URL(string: "https://www.youtube.com/")!)
                    Spacer()
                    Button("ウィンドウを選ぶ") { controller.chooseWindow() }
                        .buttonStyle(.borderedProminent)
                        .disabled(controller.isBusy)
                }
                VStack(alignment: .leading, spacing: Spacing.panel) {
                    Picker("表示先", selection: $controller.screenID) {
                        Text("メインディスプレイ").tag(CGDirectDisplayID(0))
                        ForEach(controller.screens, id: \.self) { screen in
                            Text(screen.localizedName).tag(MirrorController.displayID(screen))
                        }
                    }
                    Toggle("画面いっぱいに拡大する（端が切れる場合があります）", isOn: $controller.fillScreen)
                }
                Divider()
                HStack(alignment: .top, spacing: Spacing.gap) {
                    Text(controller.status).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("背景を停止") { Task { await controller.stop() } }
                        .disabled(!controller.isRunning && !controller.isBusy)
                }
                Text("映るのは選んだウィンドウ全体です。動画だけにするにはYouTubeを全画面にしてください。元のウィンドウは閉じたり最小化したりせず、開いたままにします。別のタブへ切り替えると、その内容も背景に映ります。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.edge)
            .frame(width: 520)
        }
        .windowResizability(.contentSize)
        .commands { CommandGroup(replacing: .newItem) {} }

        MenuBarExtra("MornDesktopTube", systemImage: "play.rectangle.on.rectangle") {
            Text(controller.status)
            Button("設定を開く") {
                openWindow(id: "controls")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("ウィンドウを選ぶ") { controller.chooseWindow() }
                .disabled(controller.isBusy)
            Button("背景を停止") { Task { await controller.stop() } }
                .disabled(!controller.isRunning && !controller.isBusy)
            Divider()
            Button("終了") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}
