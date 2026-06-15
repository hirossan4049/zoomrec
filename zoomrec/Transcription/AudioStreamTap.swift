import Foundation
import AVFoundation
import ScreenCaptureKit
import Speech

/// SCStream の音声サンプルを受け取り、SFSpeech 用に 16kHz モノラルへ変換して
/// 現在の認識リクエストへ流し込む。SCStream のコールバックは専用キューで動くため
/// `@MainActor` から切り離し、リクエスト差し替えはロックで保護する。
final class AudioStreamTap: NSObject, SCStreamOutput {
    /// SFSpeech が扱いやすい正準フォーマット（16kHz / mono / Float32）。
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private let lock = NSLock()
    private var _request: SFSpeechAudioBufferRecognitionRequest?
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?

    /// 認識リクエストを差し替える（言語切替・無音区切りでの再生成時に呼ばれる）。
    func setRequest(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        _request = request
        lock.unlock()
    }

    private var currentRequest: SFSpeechAudioBufferRecognitionRequest? {
        lock.lock(); defer { lock.unlock() }
        return _request
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio,
              sampleBuffer.isValid,
              CMSampleBufferGetNumSamples(sampleBuffer) > 0,
              let request = currentRequest,
              let input = makePCMBuffer(from: sampleBuffer),
              let converted = convert(input)
        else { return }
        request.append(converted)
    }

    // MARK: - 変換

    private func makePCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
        else { return nil }

        var asbd = asbdPtr.pointee
        guard let inFormat = AVAudioFormat(streamDescription: &asbd) else { return nil }

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return buffer
    }

    private func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if converter == nil || converterInputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: targetFormat)
            converterInputFormat = input.format
        }
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return input
        }

        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}
