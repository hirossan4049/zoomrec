import SwiftUI

/// 設定画面: Virtual Camera 名 / 解像度 / FPS / 起動時出力 / 出力モード。
struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    private let fpsOptions = [15, 24, 30, 60]

    var body: some View {
        Form {
            Section("Virtual Camera") {
                TextField("カメラ名", text: $settings.cameraName)
                Text("外部アプリ（Zoom / Meet / OBS / FaceTime）に表示される名前です。変更は Extension 再インストール後に反映されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("出力") {
                Picker("解像度", selection: resolutionBinding) {
                    ForEach(Resolution.presets) { r in
                        Text(r.label).tag(r.id)
                    }
                }
                Picker("FPS", selection: $settings.fps) {
                    ForEach(fpsOptions, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("出力モード", selection: $settings.outputMode) {
                    ForEach(OutputMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }

            Section("起動") {
                Toggle("アプリ起動時に仮想カメラ出力を開始", isOn: $settings.startOnLaunch)
            }

            Section("録画") {
                HStack {
                    Text("録画ファイル")
                    Spacer()
                    Text(settings.hasRecording ? "保存済み" : "未録画")
                        .foregroundStyle(settings.hasRecording ? .green : .secondary)
                }
                if let url = Camloo.recordingURL {
                    Text(url.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var resolutionBinding: Binding<String> {
        Binding(
            get: { settings.resolution.id },
            set: { id in
                if let r = Resolution.presets.first(where: { $0.id == id }) {
                    settings.resolution = r
                }
            }
        )
    }
}
