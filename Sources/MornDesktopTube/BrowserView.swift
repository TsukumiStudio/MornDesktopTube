import SwiftUI

struct BrowserView: View {
    @ObservedObject var controller: PlayerController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.gap) {
                Button { controller.webView.goBack() } label: { Image(systemName: "chevron.left") }
                    .help("戻る").accessibilityLabel("戻る")
                Button { controller.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help("再読み込み").accessibilityLabel("再読み込み")
                Text(controller.pageAddress.isEmpty ? "YouTube" : controller.pageAddress)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("背景に表示") { Task { await controller.showWallpaper() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding(Spacing.panel)
            BrowserSurface(container: controller.browserContainer)
            Text("Googleにログインできた場合は、このアプリ専用にセッションを保持します。Google側の制限でログインできない場合があります。")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(Spacing.panel)
        }
    }
}

private struct BrowserSurface: NSViewRepresentable {
    let container: NSView
    func makeNSView(context: Context) -> NSView { container }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
