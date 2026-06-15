import Foundation

/// 字幕の対象言語。Speech 認識ロケールと、日本語訳の要否を持つ。
enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case japanese
    case english

    var id: String { rawValue }

    /// SFSpeechRecognizer 用ロケール識別子。
    var localeIdentifier: String {
        switch self {
        case .japanese: return "ja-JP"
        case .english:  return "en-US"
        }
    }

    var displayName: String {
        switch self {
        case .japanese: return "日本語"
        case .english:  return "English"
        }
    }

    /// 英語のときだけ日本語訳を添える。
    var needsJapaneseTranslation: Bool { self == .english }
}

/// 確定した 1 区切り（発話）の字幕。`translation` は英語入力時のみ後から埋まる。
struct TranscriptSegment: Identifiable, Equatable {
    let id: UUID
    var text: String
    /// 確定時点で日本語訳を付ける対象か（＝英語認識だったか）。現在の言語ではなく発話時の意図を保持。
    let needsTranslation: Bool
    var translation: String?
    let createdAt: Date

    init(id: UUID = UUID(), text: String, needsTranslation: Bool, translation: String? = nil, createdAt: Date) {
        self.id = id
        self.text = text
        self.needsTranslation = needsTranslation
        self.translation = translation
        self.createdAt = createdAt
    }

    /// 翻訳待ち表示（「翻訳中…」）を出すべきか。
    var isAwaitingTranslation: Bool { needsTranslation && translation == nil }
}

enum TranscriptionStatus: Equatable {
    case idle
    case listening
    case starting
    case noAudioSource
    case speechUnavailable
    case permissionDenied
    case error(String)

    var headline: String {
        switch self {
        case .idle:              return "停止中"
        case .listening:         return "字幕生成中"
        case .starting:          return "開始しています…"
        case .noAudioSource:     return "音声ソースが見つかりません"
        case .speechUnavailable: return "音声認識を利用できません"
        case .permissionDenied:  return "許可が必要です"
        case .error:             return "エラー"
        }
    }

    var detail: String? {
        switch self {
        case .noAudioSource:     return "Zoom を起動して会議に参加してください"
        case .speechUnavailable: return "この言語のオンデバイス音声認識が利用できません"
        case .permissionDenied:  return "システム設定 → プライバシーとセキュリティ → 画面収録 / 音声認識"
        case .error(let m):      return m
        default:                 return nil
        }
    }

    var isHealthy: Bool { self == .listening }
}
