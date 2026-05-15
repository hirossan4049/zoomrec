import SwiftUI
import AppKit

struct DiagnosticsSheet: View {
    @EnvironmentObject var capture: CaptureService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Zoom 検出 診断", systemImage: "stethoscope")
                    .font(.title3.bold())
                Spacer()
                Button {
                    Task { await capture.runDiagnostics() }
                } label: {
                    Label("再実行", systemImage: "arrow.clockwise")
                }
            }

            ScrollView {
                Text(capture.diagnosticReport.isEmpty ? "診断中…" : capture.diagnosticReport)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.08))
                    )
            }
            .frame(minHeight: 320)

            HStack {
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(capture.diagnosticReport, forType: .string)
                } label: {
                    Label("コピー", systemImage: "doc.on.doc")
                }

                Button {
                    capture.openScreenRecordingSettings()
                } label: {
                    Label("システム設定", systemImage: "gearshape")
                }

                Button {
                    capture.restartApp()
                } label: {
                    Label("ZoomRec を再起動", systemImage: "arrow.clockwise")
                }
                .tint(.orange)

                Spacer()
                Button("閉じる") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 620, height: 520)
    }
}
