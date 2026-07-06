import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import CoreText

/// 録画ファイルをループ再生し、1 フレームずつ出力サイズのピクセルバッファへ描画する。
///
/// - 録画ファイル（App Group コンテナの `camloo-loop.mov`）を `AVAssetReader` で逐次デコード
/// - 末尾に達したらリーダーを作り直してループ
/// - 録画が無い／読めない場合はプレースホルダ映像を返す
/// - 出力サイズと元動画のサイズが異なる場合はアスペクト維持で fill（センタークロップ）
///
/// 注意: 単一のフレーム生成タイマー（`timerQueue`）からのみ呼ばれる前提でスレッド安全性を保つ。
final class LoopFrameProvider {

    private let width: Int
    private let height: Int
    private let frameRate: Int

    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    private var reader: AVAssetReader?
    private var trackOutput: AVAssetReaderTrackOutput?
    /// 現在リーダーが開いているファイルの更新日時。新しい録画を検知したら作り直す。
    private var openedModificationDate: Date?

    private var frameCounter: Int = 0

    init(width: Int, height: Int, frameRate: Int) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
    }

    /// 次のフレームを出力サイズのピクセルバッファとして返す。
    func nextFrame(pool: CVPixelBufferPool) -> CVPixelBuffer? {
        frameCounter += 1
        if let source = nextSourcePixelBuffer() {
            return render(source: source, pool: pool)
        }
        return placeholderFrame(pool: pool)
    }

    // MARK: - 録画ソースの読み出し

    /// 録画ファイルから次の 1 フレームを取り出す。EOF ならループ。録画が無ければ nil。
    private func nextSourcePixelBuffer() -> CVPixelBuffer? {
        guard let url = Camloo.recordingURL,
              FileManager.default.fileExists(atPath: url.path) else {
            teardownReader()
            return nil
        }

        // 録画が差し替わっていたらリーダーを作り直す。
        let modDate = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        if reader == nil || modDate != openedModificationDate {
            setupReader(url: url, modificationDate: modDate)
        }

        guard let output = trackOutput else { return nil }

        if let sample = output.copyNextSampleBuffer(),
           let imageBuffer = CMSampleBufferGetImageBuffer(sample) {
            return imageBuffer
        }

        // EOF もしくは読み出し失敗 → ループのためリーダーを作り直して 1 回だけ再試行。
        setupReader(url: url, modificationDate: modDate)
        if let output = trackOutput,
           let sample = output.copyNextSampleBuffer(),
           let imageBuffer = CMSampleBufferGetImageBuffer(sample) {
            return imageBuffer
        }
        return nil
    }

    private func setupReader(url: URL, modificationDate: Date?) {
        teardownReader()
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first,
              let newReader = try? AVAssetReader(asset: asset) else {
            return
        }
        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard newReader.canAdd(output) else { return }
        newReader.add(output)
        guard newReader.startReading() else { return }
        reader = newReader
        trackOutput = output
        openedModificationDate = modificationDate
    }

    private func teardownReader() {
        reader?.cancelReading()
        reader = nil
        trackOutput = nil
        openedModificationDate = nil
    }

    // MARK: - 描画

    /// 元フレームを出力サイズへアスペクト維持 fill（センタークロップ）で描画。
    private func render(source: CVPixelBuffer, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        guard let dest = makePixelBuffer(pool: pool) else { return nil }

        let srcW = CGFloat(CVPixelBufferGetWidth(source))
        let srcH = CGFloat(CVPixelBufferGetHeight(source))
        let dstW = CGFloat(width)
        let dstH = CGFloat(height)
        guard srcW > 0, srcH > 0 else { return dest }

        var image = CIImage(cvPixelBuffer: source)

        // fill スケール（大きい方に合わせて余白なし）。
        let scale = max(dstW / srcW, dstH / srcH)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // センタリング用オフセット。
        let scaledW = srcW * scale
        let scaledH = srcH * scale
        let tx = (dstW - scaledW) / 2.0
        let ty = (dstH - scaledH) / 2.0
        image = image.transformed(by: CGAffineTransform(translationX: tx, y: ty))

        // 出力矩形でクロップ。
        image = image.cropped(to: CGRect(x: 0, y: 0, width: dstW, height: dstH))

        ciContext.render(image, to: dest)
        return dest
    }

    private func makePixelBuffer(pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb) == kCVReturnSuccess else {
            return nil
        }
        return pb
    }

    // MARK: - プレースホルダ

    /// 録画が無いときに出す映像。暗い背景に "camloo" と案内テキスト、脈動するドット。
    private func placeholderFrame(pool: CVPixelBufferPool) -> CVPixelBuffer? {
        guard let pb = makePixelBuffer(pool: pool) else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return pb }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue

        guard let ctx = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return pb }

        // 背景。
        ctx.setFillColor(CGColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // 脈動ドット（フレームカウンタで明滅）。
        let pulse = 0.5 + 0.5 * sin(Double(frameCounter) * 0.15)
        let dotR = CGFloat(min(width, height)) * 0.02
        ctx.setFillColor(CGColor(red: 0.30, green: 0.60, blue: 1.0, alpha: CGFloat(0.35 + 0.65 * pulse)))
        ctx.fillEllipse(in: CGRect(
            x: CGFloat(width) / 2 - dotR,
            y: CGFloat(height) * 0.62 - dotR,
            width: dotR * 2,
            height: dotR * 2
        ))

        drawText("camloo",
                 in: ctx,
                 centerY: CGFloat(height) * 0.50,
                 fontSize: CGFloat(min(width, height)) * 0.12,
                 color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        drawText("録画するとここにループ映像が表示されます",
                 in: ctx,
                 centerY: CGFloat(height) * 0.38,
                 fontSize: CGFloat(min(width, height)) * 0.035,
                 color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))

        return pb
    }

    /// CoreText で 1 行テキストを水平中央に描画。
    private func drawText(_ string: String, in ctx: CGContext, centerY: CGFloat,
                          fontSize: CGFloat, color: CGColor) {
        let font = CTFontCreateWithName("HelveticaNeue" as CFString, fontSize, nil)
        // CoreText 用のキーで指定（UI レス拡張なので AppKit のキーは使わない）。
        ctx.setFillColor(color)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let attr = NSAttributedString(string: string, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attr)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let x = (CGFloat(width) - bounds.width) / 2.0
        ctx.textPosition = CGPoint(x: x, y: centerY)
        CTLineDraw(line, ctx)
    }
}
