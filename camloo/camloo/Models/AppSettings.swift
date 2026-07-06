import Foundation
import Combine

/// App 本体と Camera Extension で共有する設定。
///
/// 実体は App Group の UserDefaults に保存し、Extension 側からも読める。
/// Virtual Camera 名など一部は「Extension 再読み込み時」にしか反映されない
/// （macOS 側のデバイス名キャッシュのため）。詳細は README を参照。
@MainActor
final class AppSettings: ObservableObject {

    @Published var cameraName: String {
        didSet { Camloo.defaults.set(cameraName, forKey: Camloo.DefaultsKey.cameraName) }
    }

    @Published var resolution: Resolution {
        didSet {
            Camloo.defaults.set(resolution.width, forKey: Camloo.DefaultsKey.width)
            Camloo.defaults.set(resolution.height, forKey: Camloo.DefaultsKey.height)
        }
    }

    @Published var fps: Int {
        didSet { Camloo.defaults.set(fps, forKey: Camloo.DefaultsKey.fps) }
    }

    @Published var outputMode: OutputMode {
        didSet { Camloo.defaults.set(outputMode.rawValue, forKey: Camloo.DefaultsKey.outputMode) }
    }

    @Published var startOnLaunch: Bool {
        didSet { Camloo.defaults.set(startOnLaunch, forKey: Camloo.DefaultsKey.startOnLaunch) }
    }

    init() {
        let d = Camloo.defaults
        cameraName = d.string(forKey: Camloo.DefaultsKey.cameraName) ?? Camloo.Defaults.cameraName

        let w = d.integer(forKey: Camloo.DefaultsKey.width)
        let h = d.integer(forKey: Camloo.DefaultsKey.height)
        if w > 0, h > 0 {
            resolution = Resolution(width: w, height: h)
        } else {
            resolution = Resolution(width: Camloo.Defaults.width, height: Camloo.Defaults.height)
        }

        let f = d.integer(forKey: Camloo.DefaultsKey.fps)
        fps = f > 0 ? f : Camloo.Defaults.fps

        outputMode = OutputMode(rawValue: d.string(forKey: Camloo.DefaultsKey.outputMode) ?? "") ?? .loop
        startOnLaunch = d.bool(forKey: Camloo.DefaultsKey.startOnLaunch)
    }

    /// 録画ファイルが存在するか（Extension とも共有）。
    var hasRecording: Bool {
        guard let url = Camloo.recordingURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
