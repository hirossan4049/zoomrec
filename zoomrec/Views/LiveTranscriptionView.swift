import SwiftUI
import Translation

struct LiveTranscriptionView: View {
    @EnvironmentObject var service: LiveTranscriptionService
    @State private var translationConfig: TranslationSession.Configuration?

    var body: some View {
        VStack(spacing: 0) {
            transcriptScroll
            Divider()
            controlBar
        }
        // 英語のときだけ en→ja の Translation セッションを起動し、
        // 確定セグメントを順次翻訳して service へ書き戻す。
        .translationTask(translationConfig) { session in
            // 先にストリーム（continuation）を確立してから prepare する。
            // prepare 中に確定したセグメントを取りこぼさないため。
            let stream = service.makeTranslationStream()
            try? await session.prepareTranslation()
            for await pending in stream {
                let japanese = await translate(pending.text, with: session)
                service.applyTranslation(id: pending.id, japanese: japanese)
            }
        }
        .onAppear { syncTranslationConfig(for: service.language) }
        .onChange(of: service.language) { _, lang in syncTranslationConfig(for: lang) }
    }

    /// 失敗時は少し待って数回リトライ（モデル準備直後の一時的な失敗を吸収）。
    private func translate(_ text: String, with session: TranslationSession) async -> String? {
        for attempt in 0..<3 {
            do {
                return try await session.translate(text).targetText
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
        return nil
    }

    private func syncTranslationConfig(for language: TranscriptionLanguage) {
        if language.needsJapaneseTranslation {
            translationConfig = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "ja")
            )
        } else {
            translationConfig = nil
        }
    }

    // MARK: - 字幕本文

    private var transcriptScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if service.segments.isEmpty && service.partialText.isEmpty {
                        emptyState
                    }
                    ForEach(service.segments) { segment in
                        segmentRow(segment)
                    }
                    if !service.partialText.isEmpty {
                        partialRow
                            .id("partial")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: service.segments.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: service.partialText) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func segmentRow(_ segment: TranscriptSegment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(segment.text)
                .font(.title3)
                .textSelection(.enabled)
            if segment.needsTranslation {
                if let translation = segment.translation {
                    Text(translation)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("翻訳中…")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var partialRow: some View {
        Text(service.partialText)
            .font(.title3)
            .foregroundStyle(.secondary)
            .italic()
            .textSelection(.enabled)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "captions.bubble")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("開始するとここに字幕が表示されます")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    // MARK: - 操作バー

    private var controlBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(service.status.isHealthy ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 1) {
                Text(service.status.headline).font(.subheadline.weight(.medium))
                if let detail = service.status.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            Picker("言語", selection: $service.language) {
                ForEach(TranscriptionLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("認識する言語。English を選ぶと日本語訳も表示します")

            if service.status == .permissionDenied {
                Button("設定を開く") { service.openScreenRecordingSettings() }
            }

            Button {
                service.clearTranscript()
            } label: {
                Image(systemName: "trash")
            }
            .help("字幕をクリア")
            .disabled(service.segments.isEmpty && service.partialText.isEmpty)

            Button {
                service.toggle()
            } label: {
                Label(service.isRunning ? "停止" : "開始",
                      systemImage: service.isRunning ? "stop.fill" : "record.circle")
            }
            .keyboardShortcut("t", modifiers: .command)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
