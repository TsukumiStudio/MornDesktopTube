import AppKit
import Combine

@MainActor
final class SystemVolume: ObservableObject {
    @Published private(set) var level = 0.0
    @Published private(set) var muted = false
    @Published private(set) var available = false
    @Published private(set) var error: String?

    func refresh() {
        do {
            let result = try Self.execute("set s to get volume settings\nreturn {output volume of s, output muted of s}")
            guard result.numberOfItems == 2, let volume = result.atIndex(1),
                  let mute = result.atIndex(2), (0...100).contains(volume.int32Value) else {
                throw CocoaError(.coderReadCorrupt)
            }
            level = Double(volume.int32Value)
            muted = mute.booleanValue
            available = true
            error = nil
        } catch {
            available = false
            self.error = "Macの音量を取得できません。サウンド設定を確認してください。"
        }
    }

    func setLevel(_ value: Double) {
        guard let command = Self.volumeCommand(value) else { return }
        do {
            _ = try Self.execute(command)
            refresh()
            if available && abs(level - value) > 1 {
                error = "この出力機器の音量は、機器側で調整してください。"
            }
        } catch {
            refresh()
            self.error = "音量を変更できませんでした。サウンド設定を確認してください。"
        }
    }

    static func volumeCommand(_ value: Double) -> String? {
        guard value.isFinite else { return nil }
        return "set volume output volume \(Int(min(100, max(0, value)).rounded())) without output muted"
    }

    private static func execute(_ source: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw CocoaError(.coderReadCorrupt) }
        let result = script.executeAndReturnError(&error)
        if error != nil { throw CocoaError(.featureUnsupported) }
        return result
    }
}
