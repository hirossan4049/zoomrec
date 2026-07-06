import Foundation
import CoreMedia

/// App 本体と Camera Extension の双方でリンクされる共有定義。
///
/// `project.yml` で `camloo` / `camlooExtension` 両ターゲットの sources に
/// `Shared` ディレクトリを含めているため、この 1 ファイルが唯一の真実源になる。
enum Camloo {

    // MARK: - Bundle / IPC 識別子

    /// Camera Extension のバンドル ID。Info.plist の CMIOExtensionMachServiceName と揃える。
    static let extensionBundleID = "io.lh.camloo.Extension"

    /// App 本体と Extension で共有する App Group。
    /// entitlements の `com.apple.security.application-groups` と一致させること。
    static let appGroupID = "group.io.lh.camloo"

    /// 仮想カメラデバイスの固定 UUID（macOS 側のデバイス識別に使用）。
    /// Extension 側で `CMIOExtensionDevice` の deviceID に使うため、有効な UUID にすること。
    static let deviceUID = "F1C3B2A0-1C00-4C00-9E00-000C10010001"

    // MARK: - 共有ファイル

    /// ループ再生の元になる録画ファイル名（App Group コンテナ直下）。
    static let recordingFileName = "camloo-loop.mov"

    /// App Group コンテナ内の録画ファイル URL。
    static var recordingURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(recordingFileName)
    }

    // MARK: - 共有設定 (UserDefaults / App Group)

    enum DefaultsKey {
        static let cameraName = "camloo.cameraName"
        static let width = "camloo.width"
        static let height = "camloo.height"
        static let fps = "camloo.fps"
        static let outputMode = "camloo.outputMode"
        static let startOnLaunch = "camloo.startOnLaunch"
        static let hasRecording = "camloo.hasRecording"
    }

    /// App Group を suite にした UserDefaults。両プロセスから読み書きできる。
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    // MARK: - 既定値

    enum Defaults {
        static let cameraName = "Loop Camera"
        static let width = 1280
        static let height = 720
        static let fps = 30
    }
}

/// 出力モード（Live=物理カメラそのまま / Loop=録画ループ）。
///
/// MVP では Extension は常に Loop（録画ファイル）を再生する。Live は将来拡張の枠。
enum OutputMode: String, CaseIterable, Identifiable {
    case loop
    case live

    var id: String { rawValue }

    var label: String {
        switch self {
        case .loop: return "Loop（録画ループ）"
        case .live: return "Live（ライブ映像）"
        }
    }
}

/// 解像度プリセット。
struct Resolution: Identifiable, Hashable {
    let width: Int
    let height: Int

    var id: String { "\(width)x\(height)" }
    var label: String { "\(width) × \(height)" }

    static let presets: [Resolution] = [
        Resolution(width: 1280, height: 720),
        Resolution(width: 1920, height: 1080),
        Resolution(width: 640, height: 480),
    ]
}
