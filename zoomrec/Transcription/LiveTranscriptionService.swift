import Foundation
import AVFoundation
import AppKit
import ScreenCaptureKit
import Speech

/// 翻訳待ちの英語セグメント。View 側の Translation セッションが消費する。
struct PendingTranslation: Identifiable {
    let id: UUID      // 対応する TranscriptSegment.id
    let text: String
}

/// Zoom（システム）音声をリアルタイム文字起こしするサービス。
/// スクショ撮影 (`CaptureService`) とは独立して開始・停止できる。
@MainActor
final class LiveTranscriptionService: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status: TranscriptionStatus = .idle
    @Published private(set) var segments: [TranscriptSegment] = []
    @Published private(set) var partialText: String = ""

    /// 認識対象言語。稼働中に変えると認識器を作り直す。
    @Published var language: TranscriptionLanguage = .japanese {
        didSet {
            guard oldValue != language, isRunning else { return }
            Task { await restartRecognition() }
        }
    }

    /// 無音と見なすまでの猶予。これを過ぎたら現在の発話を 1 セグメントとして確定。
    private let silenceCutoff: TimeInterval = 1.0

    private let tap = AudioStreamTap()
    private let sampleQueue = DispatchQueue(label: "io.lh.zoomrec.transcription.audio")
    private var stream: SCStream?

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    /// 認識タスクの世代。作り直すたびに +1 し、古いタスクの遅延コールバックを無視する。
    private var recognitionEpoch = 0

    // 翻訳キュー（View の translationTask が purge する）。
    private var translationContinuation: AsyncStream<PendingTranslation>.Continuation?

    // MARK: - 開始 / 停止

    func toggle() {
        Task { isRunning ? stop() : await start() }
    }

    func start() async {
        guard !isRunning else { return }
        status = .starting

        guard await ensureSpeechAuthorization() else {
            status = .permissionDenied
            return
        }

        do {
            try await startAudioStream()
        } catch {
            status = classify(error)
            return
        }

        isRunning = true
        startRecognition()
        status = .listening
    }

    func stop() {
        silenceTimer?.invalidate(); silenceTimer = nil
        tearDownRecognition()
        Task { await stopAudioStream() }
        isRunning = false
        partialText = ""
        status = .idle
    }

    func clearTranscript() {
        segments.removeAll()
        partialText = ""
    }

    // MARK: - 翻訳キュー（View 連携）

    /// 言語が英語に切り替わるたびに View が新しいストリームを要求する。
    /// 生成時点で未翻訳のセグメントを再投入し、prepare 待ちなどで取りこぼした分も拾い直す。
    func makeTranslationStream() -> AsyncStream<PendingTranslation> {
        translationContinuation?.finish()
        return AsyncStream { continuation in
            self.translationContinuation = continuation
            for segment in segments where segment.isAwaitingTranslation {
                continuation.yield(PendingTranslation(id: segment.id, text: segment.text))
            }
        }
    }

    func applyTranslation(id: UUID, japanese: String?) {
        guard let japanese, !japanese.isEmpty,
              let index = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[index].translation = japanese
    }

    // MARK: - 音声ストリーム

    private func startAudioStream() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )
        guard let display = content.displays.first else {
            throw NSError(domain: "zoomrec.transcription", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "ディスプレイを取得できません"])
        }

        // Zoom アプリの音声だけを対象にする。見つからなければディスプレイ全体。
        let filter: SCContentFilter
        if let zoom = content.applications.first(where: {
            $0.bundleIdentifier.hasPrefix("us.zoom.")
        }) {
            filter = SCContentFilter(display: display, including: [zoom], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        let cfg = SCStreamConfiguration()
        cfg.capturesAudio = true
        cfg.excludesCurrentProcessAudio = true
        cfg.sampleRate = 48_000
        cfg.channelCount = 2
        // 映像は使わないので最小化（音声のみで起動する）。
        cfg.width = 2
        cfg.height = 2
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: cfg, delegate: self)
        try stream.addStreamOutput(tap, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    private func stopAudioStream() async {
        guard let stream else { return }
        self.stream = nil
        try? stream.removeStreamOutput(tap, type: .audio)
        try? await stream.stopCapture()
    }

    // MARK: - 認識

    private func startRecognition() {
        // 認識器はロケールが変わったときだけ作り直す（毎発話の再生成は遅延の元）。
        let locale = Locale(identifier: language.localeIdentifier)
        if recognizer?.locale.identifier != locale.identifier {
            recognizer = SFSpeechRecognizer(locale: locale)
        }
        guard let recognizer, recognizer.isAvailable else {
            status = .speechUnavailable
            stop()
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.addsPunctuation = true
        self.request = request
        tap.setRequest(request)

        recognitionEpoch += 1
        let epoch = recognitionEpoch
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                // 作り直し前の古いタスクからの遅延コールバックは無視する。
                guard let self, epoch == self.recognitionEpoch else { return }
                self.handleRecognition(result: result, error: error)
            }
        }
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            partialText = result.bestTranscription.formattedString
            scheduleSilenceCommit()
            if result.isFinal {
                commitCurrentUtterance()
                return
            }
        }
        // 認識タスクが（自前のキャンセル以外で）落ちたら次の発話用に作り直す。
        if error != nil, isRunning {
            commitCurrentUtterance()
        }
    }

    private func scheduleSilenceCommit() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceCutoff, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.commitCurrentUtterance() }
        }
    }

    /// 現在の partial を 1 セグメントとして確定し、次の発話用に認識を作り直す。
    private func commitCurrentUtterance() {
        silenceTimer?.invalidate(); silenceTimer = nil

        let text = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        partialText = ""

        if !text.isEmpty {
            let needsTr = language.needsJapaneseTranslation
            let segment = TranscriptSegment(text: text, needsTranslation: needsTr, createdAt: Date())
            segments.append(segment)
            if needsTr {
                translationContinuation?.yield(PendingTranslation(id: segment.id, text: text))
            }
        }

        guard isRunning else { return }
        restartRecognitionTask()
    }

    /// 音声ストリームは維持したまま、認識リクエスト/タスクだけ作り直す。
    private func restartRecognitionTask() {
        tearDownRecognition()
        startRecognition()
    }

    /// 言語切替時：途中の partial は破棄して認識を作り直す（ストリームはそのまま）。
    private func restartRecognition() async {
        silenceTimer?.invalidate(); silenceTimer = nil
        partialText = ""
        guard isRunning else { return }
        restartRecognitionTask()
    }

    private func tearDownRecognition() {
        recognitionEpoch += 1   // 以後この世代のコールバックは無視される
        tap.setRequest(nil)
        // endAudio() は最終結果の確定待ちで間が空くため、即時に cancel して作り直す。
        // 取りこぼし防止に partial は呼び出し側で確定済み。
        task?.cancel()
        task = nil
        request = nil
    }

    // MARK: - 権限 / エラー

    private func ensureSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }

    private func classify(_ error: Error) -> TranscriptionStatus {
        let ns = error as NSError
        let lower = ns.localizedDescription.lowercased()
        if lower.contains("permission") || lower.contains("not authorized")
            || lower.contains("declined") || ns.code == -3801 || ns.code == -3804 {
            return .permissionDenied
        }
        return .error(ns.localizedDescription)
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - SCStreamDelegate

extension LiveTranscriptionService: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.isRunning else { return }
            self.status = self.classify(error)
            self.stop()
        }
    }
}
