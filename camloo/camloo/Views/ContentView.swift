import SwiftUI

struct ContentView: View {
    @EnvironmentObject var camera: CameraManager
    @State private var showingSettings = false

    var body: some View {
        Group {
            if camera.authorization == .authorized {
                MainView(showingSettings: $showingSettings)
            } else {
                PermissionsView()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheetWrapper()
        }
    }
}

/// メイン画面のツールバーから開く設定シート。
private struct SettingsSheetWrapper: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("設定").font(.headline)
                Spacer()
                Button("完了") { dismiss() }
            }
            .padding()
            Divider()
            SettingsView()
                .padding()
        }
        .frame(width: 440, height: 420)
    }
}
