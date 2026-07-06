import SwiftUI
import AVFoundation
import AppKit

/// 権限案内画面: カメラ権限 / System Extension 許可の案内。
struct PermissionsView: View {
    @EnvironmentObject var camera: CameraManager
    @EnvironmentObject var sysext: SystemExtensionManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("camloo を使うには権限が必要です")
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: 16) {
                permissionRow(
                    title: "カメラ",
                    detail: cameraDetail,
                    granted: camera.authorization == .authorized
                ) {
                    if camera.authorization == .notDetermined {
                        camera.requestAuthorizationIfNeeded()
                    } else {
                        openSettings("Privacy_Camera")
                    }
                }

                permissionRow(
                    title: "仮想カメラ (System Extension)",
                    detail: "macOS に仮想カメラを登録します。初回は「システム設定 → プライバシーとセキュリティ」での許可が必要です。",
                    granted: sysext.state == .installed
                ) {
                    sysext.install()
                }
            }
            .padding()
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 480)

            Text("許可後もカメラが認識されない場合は、camloo を完全に終了して再起動してください。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cameraDetail: String {
        switch camera.authorization {
        case .authorized: return "許可済み"
        case .denied, .restricted:
            return "拒否されています。システム設定で許可してください。"
        default:
            return "選択したカメラの映像をプレビュー・録画するために使用します。"
        }
    }

    @ViewBuilder
    private func permissionRow(title: String, detail: String, granted: Bool,
                               action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("許可") { action() }
            }
        }
    }

    private func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
