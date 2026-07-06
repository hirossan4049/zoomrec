import Foundation
import AVFoundation
import Combine

/// 物理カメラの列挙・ライブプレビュー・録画を担当する。
///
/// - プレビュー: `AVCaptureVideoPreviewLayer`（`CameraPreview` から参照）
/// - 録画: `AVCaptureMovieFileOutput` → App Group コンテナへ保存
///
/// 録画ファイルは Camera Extension がループ再生の元として読む共有ファイル。
@MainActor
final class CameraManager: NSObject, ObservableObject {

    /// 接続中の物理カメラ一覧。
    @Published private(set) var devices: [AVCaptureDevice] = []
    /// 選択中カメラ。
    @Published var selectedDevice: AVCaptureDevice? {
        didSet {
            guard oldValue?.uniqueID != selectedDevice?.uniqueID else { return }
            reconfigureInput()
        }
    }
    @Published private(set) var isRunning = false
    @Published private(set) var isRecording = false
    @Published private(set) var lastError: String?
    /// カメラ権限の状態。
    @Published private(set) var authorization: AVAuthorizationStatus =
        AVCaptureDevice.authorizationStatus(for: .video)

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var currentInput: AVCaptureDeviceInput?
    private let sessionQueue = DispatchQueue(label: "io.lh.camloo.session")

    /// 録画中の一時保存先（完了時に共有ファイルへ置き換える）。
    private var pendingRecordingTemp: URL?

    override init() {
        super.init()
        session.sessionPreset = .high
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        refreshDevices()
    }

    // MARK: - 権限

    func requestAuthorizationIfNeeded() {
        switch authorization {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    self?.authorization = granted ? .authorized : .denied
                    if granted { self?.refreshDevices() }
                }
            }
        default:
            break
        }
    }

    // MARK: - デバイス列挙

    func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )
        devices = discovery.devices
        if selectedDevice == nil {
            selectedDevice = devices.first
        } else if let sel = selectedDevice,
                  !devices.contains(where: { $0.uniqueID == sel.uniqueID }) {
            // 選択中カメラが外れた
            selectedDevice = devices.first
        }
    }

    // MARK: - セッション制御

    func start() {
        guard authorization == .authorized else {
            requestAuthorizationIfNeeded()
            return
        }
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            Task { @MainActor in self.isRunning = true }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            Task { @MainActor in self.isRunning = false }
        }
    }

    private func reconfigureInput() {
        guard let device = selectedDevice else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            if let existing = self.currentInput {
                self.session.removeInput(existing)
                self.currentInput = nil
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.currentInput = input
                }
            } catch {
                Task { @MainActor in self.lastError = error.localizedDescription }
            }
            self.session.commitConfiguration()
        }
    }

    // MARK: - 録画

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    func startRecording() {
        guard !isRecording, currentInput != nil else { return }
        // App Group コンテナ内の一時ファイルへ録画し、完了時に共有ファイルへ置換。
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Camloo.appGroupID) else {
            lastError = "App Group コンテナにアクセスできません"
            return
        }
        let temp = container.appendingPathComponent("recording-\(Int(Date().timeIntervalSince1970)).mov")
        try? FileManager.default.removeItem(at: temp)
        pendingRecordingTemp = temp
        movieOutput.startRecording(to: temp, recordingDelegate: self)
        isRecording = true
    }

    func stopRecording() {
        guard isRecording else { return }
        movieOutput.stopRecording()
        // isRecording は delegate 完了時に false へ
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        Task { @MainActor in
            self.isRecording = false
            if let error {
                self.lastError = error.localizedDescription
                return
            }
            self.promoteRecording(from: outputFileURL)
        }
    }

    /// 一時録画ファイルを Extension が読む共有ファイル (`camloo-loop.mov`) へ置き換える。
    private func promoteRecording(from temp: URL) {
        guard let dest = Camloo.recordingURL else { return }
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.moveItem(at: temp, to: dest)
            Camloo.defaults.set(true, forKey: Camloo.DefaultsKey.hasRecording)
        } catch {
            lastError = "録画の保存に失敗: \(error.localizedDescription)"
        }
        pendingRecordingTemp = nil
    }
}
