import Foundation
import AppKit
import ScreenCaptureKit

enum CaptureStatus: Equatable {
    case idle
    case zoomFound(title: String?)
    case zoomMinimized
    case zoomNoWindow
    case zoomNotRunning
    case permissionDenied
    case error(String)

    var headline: String {
        switch self {
        case .idle: return "停止中"
        case .zoomFound: return "Zoom 検出済み"
        case .zoomMinimized: return "Zoom ウィンドウが最小化されています"
        case .zoomNoWindow: return "Zoom 起動中・ウィンドウなし"
        case .zoomNotRunning: return "Zoom が起動していません"
        case .permissionDenied: return "画面収録の許可が必要"
        case .error: return "エラー"
        }
    }

    var detail: String? {
        switch self {
        case .zoomFound(let title): return (title?.isEmpty == false) ? title : nil
        case .zoomMinimized: return "Zoom のウィンドウを前面に出してください"
        case .zoomNoWindow: return "Zoom メイン画面を開いてください"
        case .zoomNotRunning: return "Zoom を起動してください"
        case .permissionDenied: return "システム設定 → プライバシーとセキュリティ → 画面収録"
        case .error(let m): return m
        default: return nil
        }
    }

    var isHealthy: Bool {
        if case .zoomFound = self { return true }
        return false
    }
}

@MainActor
final class CaptureService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status: CaptureStatus = .idle
    @Published private(set) var lastCaptureAt: Date?
    @Published private(set) var nextCaptureAt: Date?
    @Published private(set) var totalCaptured: Int = 0
    @Published var diagnosticReport: String = ""

    let intervalSeconds: TimeInterval = 60
    private var timer: Timer?
    private let store: LibraryStore

    init(store: LibraryStore) {
        self.store = store
    }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        scheduleNext()
        Task { await captureOnce() }
        let t = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.captureOnce() }
        }
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        nextCaptureAt = nil
        status = .idle
    }

    private func scheduleNext() {
        nextCaptureAt = Date().addingTimeInterval(intervalSeconds)
    }

    func captureOnce() async {
        defer { if isRunning { scheduleNext() } }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false
            )
            let probe = WindowFinder.probe(in: content)

            if probe.thirdPartyVisible == 0 && !probe.zoomRunning {
                status = .permissionDenied
                return
            }
            if probe.thirdPartyVisible == 0 {
                status = .permissionDenied
                return
            }
            if !probe.zoomRunning {
                status = .zoomNotRunning
                return
            }
            guard let window = probe.chosen else {
                status = probe.zoomTotal > 0 ? .zoomMinimized : .zoomNoWindow
                return
            }

            let cfg = SCStreamConfiguration()
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            cfg.width = max(1, Int(window.frame.width * scale))
            cfg.height = max(1, Int(window.frame.height * scale))
            cfg.showsCursor = false
            cfg.capturesAudio = false

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: cfg
            )
            try store.save(image: image, at: Date())
            lastCaptureAt = Date()
            totalCaptured += 1
            status = .zoomFound(title: window.title)
        } catch let error as NSError {
            let msg = error.localizedDescription
            let lower = msg.lowercased()
            let isPerm = lower.contains("permission")
                || lower.contains("not authorized")
                || lower.contains("declined")
                || lower.contains("screen recording")
                || error.code == -3801
                || error.code == -3804
            status = isPerm ? .permissionDenied : .error(msg)
        }
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func restartApp() {
        let path = Bundle.main.bundleURL.path
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1 && open -n \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    func runDiagnostics() async {
        var lines: [String] = []
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        lines.append("=== ZoomRec 診断 \(fmt.string(from: Date())) ===")
        lines.append("Bundle ID : \(Bundle.main.bundleIdentifier ?? "(unknown)")")
        lines.append("App Path  : \(Bundle.main.bundleURL.path)")
        let zoomRunning = !NSRunningApplication
            .runningApplications(withBundleIdentifier: "us.zoom.xos")
            .isEmpty
        lines.append("Zoom 起動 : \(zoomRunning ? "YES" : "NO")")
        lines.append("")

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false
            )
            lines.append("SCShareableContent OK")
            lines.append("総ウィンドウ数: \(content.windows.count)")
            let appCounts: [String: Int] = content.windows.reduce(into: [:]) { dict, w in
                let bid = w.owningApplication?.bundleIdentifier ?? "(no-bundle)"
                dict[bid, default: 0] += 1
            }
            lines.append("")
            lines.append("--- 検出された App (上位20) ---")
            for (bid, n) in appCounts.sorted(by: { $0.value > $1.value }).prefix(20) {
                lines.append(String(format: "  %3d  %@", n, bid))
            }

            let zoomWindows = content.windows.filter {
                ($0.owningApplication?.bundleIdentifier ?? "").hasPrefix("us.zoom.")
            }
            lines.append("")
            lines.append("--- Zoom ウィンドウ: \(zoomWindows.count) 件 ---")
            for w in zoomWindows {
                let onScreen = w.isOnScreen ? "ON " : "off"
                let title = (w.title?.isEmpty == false) ? w.title! : "(タイトル無し)"
                let size = "\(Int(w.frame.width))×\(Int(w.frame.height))"
                lines.append("  [\(onScreen)] \(size)  \(title)")
            }

            let probe = WindowFinder.probe(in: content)
            lines.append("")
            lines.append("--- probe 結果 ---")
            lines.append("zoomTotal         : \(probe.zoomTotal)")
            lines.append("zoomVisible       : \(probe.zoomVisible)")
            lines.append("thirdPartyVisible : \(probe.thirdPartyVisible)")
            lines.append("chosen            : \(probe.chosen?.title ?? "(none)")")

            lines.append("")
            if probe.thirdPartyVisible == 0 {
                lines.append("⚠️ 他社アプリのウィンドウが 1 件も見えていません。")
                lines.append("   → 画面収録の許可が反映されていない可能性が高いです。")
                lines.append("   対処: システム設定で許可を ON にし、ZoomRec を完全終了 → 再起動。")
            } else if probe.zoomVisible == 0 {
                lines.append("ℹ️ 他社ウィンドウは見えているが Zoom が見えません。")
                lines.append("   → 権限は OK。Zoom のウィンドウを開く/最前面に出してください。")
            } else {
                lines.append("✅ Zoom ウィンドウを検出できています。")
            }
        } catch {
            lines.append("❌ SCShareableContent ERROR")
            lines.append("  \(error)")
            lines.append("  → 画面収録の許可が必要、または OS の制約。")
        }
        diagnosticReport = lines.joined(separator: "\n")
    }
}
