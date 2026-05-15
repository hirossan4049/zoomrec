import SwiftUI

struct CaptureStatusBar: View {
    @EnvironmentObject var capture: CaptureService
    @State private var showingDiagnostics = false

    var body: some View {
        HStack(spacing: 14) {
            recordButton
            recordingIndicator
            Divider().frame(height: 28)
            statusBlock
            Spacer(minLength: 8)
            countdownLabel
            lastShotLabel
            totalLabel
            captureNowButton
            permissionButtons
            diagnoseButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsSheet()
        }
    }

    private var recordButton: some View {
        Button {
            capture.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: capture.isRunning ? "stop.fill" : "record.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(capture.isRunning ? "停止" : "撮影開始")
                    .font(.body.weight(.semibold))
            }
            .frame(minWidth: 110)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(capture.isRunning ? Color.red : Color.accentColor)
            )
        }
        .buttonStyle(.plain)
        .keyboardShortcut("r", modifiers: [.command])
        .help(capture.isRunning ? "撮影を停止 (⌘R)" : "60秒ごとの撮影を開始 (⌘R)")
    }

    @ViewBuilder
    private var recordingIndicator: some View {
        if capture.isRunning {
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
                Text("録画中")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
            }
        }
    }

    private var statusBlock: some View {
        HStack(spacing: 8) {
            statusIcon
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(capture.status.headline)
                    .font(.caption.weight(.medium))
                if let detail = capture.status.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .frame(minWidth: 220, alignment: .leading)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch capture.status {
        case .idle:
            Image(systemName: "pause.circle").foregroundStyle(.secondary)
        case .zoomFound:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .zoomMinimized, .zoomNoWindow, .zoomNotRunning:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .permissionDenied:
            Image(systemName: "lock.fill").foregroundStyle(.orange)
        case .error:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var countdownLabel: some View {
        if capture.isRunning, let next = capture.nextCaptureAt {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let remaining = max(0, Int(next.timeIntervalSince(ctx.date)))
                Label("次 \(remaining)s", systemImage: "timer")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var lastShotLabel: some View {
        if let last = capture.lastCaptureAt {
            Label(Self.timeFmt.string(from: last), systemImage: "checkmark.seal")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help("直近の撮影成功時刻")
        }
    }

    @ViewBuilder
    private var totalLabel: some View {
        if capture.totalCaptured > 0 {
            Label("\(capture.totalCaptured)", systemImage: "photo.stack")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help("セッション開始からの撮影枚数")
        }
    }

    private var captureNowButton: some View {
        Button {
            Task { await capture.captureOnce() }
        } label: {
            Label("今すぐ撮影", systemImage: "camera.shutter.button.fill")
        }
        .buttonStyle(.bordered)
        .keyboardShortcut("k", modifiers: [.command])
        .help("Zoom ウィンドウを今すぐ 1 枚撮影 (⌘K)")
    }

    @ViewBuilder
    private var permissionButtons: some View {
        if case .permissionDenied = capture.status {
            Button {
                capture.openScreenRecordingSettings()
            } label: {
                Label("システム設定", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .tint(.orange)

            Button {
                capture.restartApp()
            } label: {
                Label("再起動", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .help("許可を反映するにはアプリの完全再起動が必要です")
        }
    }

    private var diagnoseButton: some View {
        Button {
            showingDiagnostics = true
            Task { await capture.runDiagnostics() }
        } label: {
            Image(systemName: "stethoscope")
        }
        .buttonStyle(.bordered)
        .help("検出状況を診断する")
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
