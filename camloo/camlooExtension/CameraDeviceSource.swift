import Foundation
import CoreMediaIO
import CoreMedia
import CoreVideo
import IOKit.audio

enum CamlooExtensionError: Error {
    case invalidDeviceSource
    case pixelBufferPoolUnavailable
}

/// 仮想カメラデバイス本体。
///
/// 一定 FPS のタイマーでフレームを生成し、`CameraStreamSource` のストリームへ送出する。
/// フレームの中身は録画ファイルのループ再生（`LoopFrameProvider`）。録画が無い場合は
/// プレースホルダ映像を出す。
class CameraDeviceSource: NSObject, CMIOExtensionDeviceSource {

    private(set) var device: CMIOExtensionDevice!
    private var streamSource: CameraStreamSource!
    private var streamingCounter: UInt32 = 0

    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "io.lh.camloo.frames", qos: .userInteractive)

    private let width: Int
    private let height: Int
    private let frameRate: Int

    private var videoDescription: CMFormatDescription!
    private var bufferPool: CVPixelBufferPool!

    private let frameProvider: LoopFrameProvider

    init(localizedName: String) {
        // 解像度・FPS は App Group 経由の共有設定から取得。
        let d = Camloo.defaults
        let w = d.integer(forKey: Camloo.DefaultsKey.width)
        let h = d.integer(forKey: Camloo.DefaultsKey.height)
        let f = d.integer(forKey: Camloo.DefaultsKey.fps)
        width = w > 0 ? w : Camloo.Defaults.width
        height = h > 0 ? h : Camloo.Defaults.height
        frameRate = f > 0 ? f : Camloo.Defaults.fps
        frameProvider = LoopFrameProvider(width: width, height: height, frameRate: frameRate)

        super.init()

        let deviceID = UUID(uuidString: Camloo.deviceUID) ?? UUID()
        device = CMIOExtensionDevice(
            localizedName: localizedName,
            deviceID: deviceID,
            legacyDeviceID: nil,
            source: self
        )

        // 32BGRA のフォーマット記述子。
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: Int32(width),
            height: Int32(height),
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        videoDescription = formatDescription

        // IOSurface backed のピクセルバッファプール（CMIO 共有に必須）。
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, pixelBufferAttributes as CFDictionary, &pool)
        bufferPool = pool

        let frameDuration = CMTime(value: 1, timescale: Int32(frameRate))
        let videoStreamFormat = CMIOExtensionStreamFormat(
            formatDescription: videoDescription,
            maxFrameDuration: frameDuration,
            minFrameDuration: frameDuration,
            validFrameDurations: nil
        )

        let videoStreamID = UUID()
        streamSource = CameraStreamSource(
            localizedName: "camloo.video",
            streamID: videoStreamID,
            streamFormat: videoStreamFormat,
            frameRate: frameRate,
            device: device
        )
        do {
            try device.addStream(streamSource.stream)
        } catch {
            fatalError("camloo: failed to add stream: \(error.localizedDescription)")
        }
    }

    // MARK: - Properties

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            deviceProperties.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        if properties.contains(.deviceModel) {
            deviceProperties.model = "camloo Loop Camera"
        }
        return deviceProperties
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    // MARK: - Streaming

    func startStreaming() {
        guard bufferPool != nil else { return }
        streamingCounter += 1

        let source = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        source.schedule(deadline: .now(), repeating: 1.0 / Double(frameRate), leeway: .milliseconds(1))
        source.setEventHandler { [weak self] in
            self?.emitFrame()
        }
        source.resume()
        timer = source
    }

    func stopStreaming() {
        if streamingCounter > 1 {
            streamingCounter -= 1
        } else {
            streamingCounter = 0
            timer?.cancel()
            timer = nil
        }
    }

    private func emitFrame() {
        guard let pool = bufferPool else { return }
        guard let pixelBuffer = frameProvider.nextFrame(pool: pool) else { return }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo()
        timing.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock())

        let status = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: videoDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )

        if status == noErr, let sampleBuffer {
            streamSource.stream.send(
                sampleBuffer,
                discontinuity: [],
                hostTimeInNanoseconds: UInt64(timing.presentationTimeStamp.seconds * Double(NSEC_PER_SEC))
            )
        }
    }
}
