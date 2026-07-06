import SwiftUI
import AVFoundation

/// メイン画面: カメラ選択・プレビュー・録画操作・仮想カメラ出力状態。
struct MainView: View {
    @EnvironmentObject var camera: CameraManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var sysext: SystemExtensionManager
    @Binding var showingSettings: Bool

    var body: some View {
        VStack(spacing: 0) {
            preview
            Divider()
            controls
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    // MARK: - プレビュー

    private var preview: some View {
        ZStack {
            Color.black
            CameraPreview(session: camera.session)
            if camera.selectedDevice == nil {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("カメラが選択されていません")
                        .foregroundStyle(.secondary)
                }
            }
            if camera.isRecording {
                VStack {
                    HStack(spacing: 6) {
                        Circle().fill(.red).frame(width: 10, height: 10)
                        Text("REC").font(.caption.weight(.bold)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(12)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 操作列

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Picker("カメラ", selection: cameraSelectionBinding) {
                    if camera.devices.isEmpty {
                        Text("（検出なし）").tag(String?.none)
                    }
                    ForEach(camera.devices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(Optional(device.uniqueID))
                    }
                }
                .frame(maxWidth: 320)

                Button {
                    camera.refreshDevices()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("カメラ一覧を再読み込み")

                Spacer()

                Button {
                    showingSettings = true
                } label: {
                    Label("設定", systemImage: "gearshape")
                }
            }

            HStack(spacing: 12) {
                Button {
                    camera.toggleRecording()
                } label: {
                    Label(camera.isRecording ? "録画停止" : "録画開始",
                          systemImage: camera.isRecording ? "stop.fill" : "record.circle")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .tint(camera.isRecording ? .red : .accentColor)
                .disabled(camera.selectedDevice == nil)

                virtualCameraStatus

                Spacer()

                if let err = camera.lastError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .help(err)
                }
            }
        }
        .padding()
    }

    // MARK: - 仮想カメラ状態 + インストール操作

    @ViewBuilder
    private var virtualCameraStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(sysext.state == .installed ? Color.green : Color.gray)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text("仮想カメラ: \(sysext.state.headline)")
                    .font(.caption)
                Text("名称: \(settings.cameraName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if sysext.state != .installed {
                Button("有効化") { sysext.install() }
                    .controlSize(.small)
            } else {
                Button("再インストール") { sysext.install() }
                    .controlSize(.small)
                    .help("カメラ名など設定変更を反映するには再インストールが必要な場合があります")
            }
        }
    }

    /// Picker 用: uniqueID ↔ AVCaptureDevice のブリッジ。
    private var cameraSelectionBinding: Binding<String?> {
        Binding(
            get: { camera.selectedDevice?.uniqueID },
            set: { id in
                camera.selectedDevice = camera.devices.first { $0.uniqueID == id }
            }
        )
    }
}
