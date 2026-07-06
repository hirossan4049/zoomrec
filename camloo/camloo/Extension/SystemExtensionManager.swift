import Foundation
import SystemExtensions
import Combine
import CoreMediaIO

/// Camera Extension (System Extension) のインストール／削除と状態管理。
///
/// `OSSystemExtensionRequest` で `io.lh.camloo.Extension` をアクティベートする。
/// 実際にインストールが完了すると macOS の各アプリのカメラ一覧に
/// Virtual Camera（Loop Camera）が現れる。
@MainActor
final class SystemExtensionManager: NSObject, ObservableObject {

    enum State: Equatable {
        case unknown
        case installing
        case installed
        case needsUserApproval
        case failed(String)

        var headline: String {
            switch self {
            case .unknown: return "未確認"
            case .installing: return "インストール中…"
            case .installed: return "有効"
            case .needsUserApproval: return "ユーザー承認待ち"
            case .failed: return "失敗"
            }
        }
    }

    @Published private(set) var state: State = .unknown

    /// 仮想カメラ拡張を有効化する。
    func install() {
        state = .installing
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: Camloo.extensionBundleID,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// 仮想カメラ拡張を無効化（アンインストール）する。
    func uninstall() {
        state = .installing
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: Camloo.extensionBundleID,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// システムに camloo の仮想カメラが登録済みか調べる。
    func refreshInstalledState() {
        // CoreMediaIO で仮想カメラデバイスの存在を確認する。
        let found = Self.virtualCameraExists(uid: Camloo.deviceUID)
        if found {
            state = .installed
        } else if case .installing = state {
            // 進行中はそのまま
        } else if case .needsUserApproval = state {
            // 承認待ちはそのまま
        } else {
            state = .unknown
        }
    }

    /// 指定 UID の CMIO デバイスが存在するかを走査する。
    private static func virtualCameraExists(uid: String) -> Bool {
        var opa = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject), &opa, 0, nil, &dataSize
        ) == noErr, dataSize > 0 else { return false }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var deviceIDs = [CMIOObjectID](repeating: 0, count: count)
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &opa, 0, nil, dataSize, &dataUsed, &deviceIDs
        ) == noErr else { return false }

        for deviceID in deviceIDs {
            var uidAddr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            var uidSize: UInt32 = 0
            guard CMIOObjectGetPropertyDataSize(deviceID, &uidAddr, 0, nil, &uidSize) == noErr else { continue }
            var cfUID: CFString? = nil
            var used: UInt32 = 0
            let status = withUnsafeMutablePointer(to: &cfUID) { ptr -> OSStatus in
                CMIOObjectGetPropertyData(deviceID, &uidAddr, 0, nil, uidSize, &used, ptr)
            }
            if status == noErr, let s = cfUID as String?, s == uid {
                return true
            }
        }
        return false
    }
}

// MARK: - OSSystemExtensionRequestDelegate

extension SystemExtensionManager: OSSystemExtensionRequestDelegate {

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        // 常に新しいものへ置き換える（バージョンダウンも許可＝開発向け）。
        return .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in self.state = .needsUserApproval }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { @MainActor in
            switch result {
            case .completed:
                self.state = .installed
            case .willCompleteAfterReboot:
                self.state = .needsUserApproval
            @unknown default:
                self.state = .installed
            }
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        Task { @MainActor in self.state = .failed(error.localizedDescription) }
    }
}
