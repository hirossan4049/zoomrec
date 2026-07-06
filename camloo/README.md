# camloo

特定の物理カメラ映像を録画し、その録画をループ再生して macOS の **Virtual Camera** として出力するアプリ。Zoom / Google Meet / OBS / FaceTime などから「Loop Camera」という名前のカメラとして選択できる。

対応 OS: macOS 12.3 以降（Core Media I/O Camera Extension が必要）

> このディレクトリ (`camloo/`) は同リポジトリ内の ZoomRec とは独立した別アプリです。

---

## 仕組み

```
Physical Camera → Capture (AVFoundation) → Live Preview
                                          → Recording → camloo-loop.mov (App Group 共有)
                                                          ↓
                                          Camera Extension (CMIO)
                                          Loop Playback → Virtual Camera
                                                          ↓
                                          Zoom / Meet / OBS / FaceTime
```

- **App 本体 (`camloo`)** — SwiftUI。カメラ選択・ライブプレビュー・録画・設定・System Extension のインストールを担当。
- **Camera Extension (`camlooExtension`)** — Core Media I/O の System Extension。App Group 共有ファイル `camloo-loop.mov` を `AVAssetReader` でループ再生し、一定 FPS で仮想カメラストリームへ送出する。録画が無い間は「camloo」プレースホルダ映像を出す。
- **連携** — App Group (`group.io.lh.camloo`) 経由でファイルと設定 (UserDefaults) を共有。

### ソース構成

| パス | 役割 |
| --- | --- |
| `Shared/CamlooShared.swift` | App / Extension 共通の定数・App Group・設定キー（両ターゲットにリンク） |
| `camloo/camlooApp.swift` | App エントリポイント |
| `camloo/Models/AppSettings.swift` | 共有設定（カメラ名 / 解像度 / FPS / 出力モード / 起動時出力） |
| `camloo/Camera/CameraManager.swift` | デバイス列挙・プレビュー・録画（→ App Group へ保存） |
| `camloo/Camera/CameraPreview.swift` | `AVCaptureVideoPreviewLayer` の SwiftUI ラッパ |
| `camloo/Extension/SystemExtensionManager.swift` | 仮想カメラ拡張のインストール／削除・状態確認 |
| `camloo/Views/*` | メイン / 設定 / 権限案内 画面 |
| `camlooExtension/main.swift` | 拡張エントリポイント（`CMIOExtensionProvider.startService`） |
| `camlooExtension/CameraProviderSource.swift` | Provider（デバイス登録） |
| `camlooExtension/CameraDeviceSource.swift` | デバイス本体・フレーム生成タイマー・送出 |
| `camlooExtension/CameraStreamSource.swift` | 映像ストリーム |
| `camlooExtension/LoopFrameProvider.swift` | 録画ループ読み出し・スケール・プレースホルダ描画 |

---

## ビルド

```bash
brew install xcodegen
cd camloo
xcodegen            # project.yml から camloo.xcodeproj を生成
open camloo.xcodeproj
```

Xcode で **camloo** スキームを Run。最低要件: Xcode 14+ / macOS 12.3 SDK。

`Info.plist` と `camloo.xcodeproj` は `xcodegen` が `project.yml` から生成するため、リポジトリにはコミットしていません。

### 署名について（重要）

System Extension は本来 **正式な Developer ID 署名 + 公証**、または **プロビジョニングされた開発署名** が必要です。ローカル開発では以下のいずれかで検証を緩められます。

```bash
# 開発モード（要 SIP 部分無効化 / リカバリで csrutil 設定済みが前提）
systemextensionsctl developer on
```

`project.yml` は ZoomRec と同じく ad-hoc 署名 (`CODE_SIGN_IDENTITY: "-"`) をベースにしています。実運用では自分の Team ID を `DEVELOPMENT_TEAM` に設定し、`CMIOExtensionMachServiceName` の `$(TeamIdentifierPrefix)` が解決されるようにしてください。

> XcodeGen が拡張を `Contents/Library/SystemExtensions/` に埋め込まない場合は、Xcode の app ターゲット → Build Phases の **Embed System Extensions** コピー先がそのパスになっているか確認してください。

---

## 使い方

1. camloo を **/Applications** に置いて起動（System Extension のインストールは /Applications 配下が前提）。
2. **カメラ権限** を許可（初回起動時にダイアログ）。
3. メイン画面右下の **「有効化」** で仮想カメラ拡張をインストール。初回は
   **システム設定 → プライバシーとセキュリティ** で許可を求められます。
4. 使いたい物理カメラを選び、**録画開始 → 録画停止**。停止時に `camloo-loop.mov` として保存されます。
5. Zoom / Meet / OBS / FaceTime のカメラ選択で **「Loop Camera」** を選ぶと、録画がループ再生されます。

### 設定（メイン画面の「設定」ボタン）

| 項目 | 初期値 | 内容 |
| --- | --- | --- |
| Virtual Camera 名 | Loop Camera | 外部アプリに表示される名前 |
| 解像度 | 1280×720 | 仮想カメラ出力解像度 |
| FPS | 30 | 出力フレームレート |
| 出力モード | Loop | Live / Loop（MVP は Loop を出力） |
| 起動時出力 | OFF | 起動時に仮想カメラを開始するか |

---

## カメラ名の変更について

Virtual Camera 名は Camera Extension の `localizedName` に反映されますが、**macOS 側のデバイス名キャッシュ**のため即時反映されないことがあります。反映されない場合は次のいずれかを行ってください。

- camloo を完全終了して再起動
- 仮想カメラ拡張を **再インストール**（メイン画面の「再インストール」）
- 使用側アプリ（Zoom など）を再起動
- 権限を再承認

---

## 権限

| 権限 | 用途 |
| --- | --- |
| Camera | 物理カメラ入力 |
| Microphone | 音声録画を行う場合 |
| System Extension | Virtual Camera の登録 |
| App Groups | App 本体と Extension のデータ共有 |

---

## MVP の範囲と制限

**実装済み（MVP）**

- カメラ選択 / ライブプレビュー
- 録画開始・停止（App Group へ保存）
- 録画動画のループ再生
- Virtual Camera 出力
- カメラ名・解像度・FPS の設定（Extension 再読み込み時に反映）

**制限・今後**

- 出力モードの **Live**（物理カメラをそのまま仮想カメラへ）は枠のみ。MVP では常に Loop を出力。
- 音声は仮想カメラ側では扱わない（映像のみ）。
- ループ再生はフレームを 1 枚ずつ等間隔で送出する簡易実装のため、元動画の FPS と出力 FPS が大きく異なると再生速度が変わります。
- 解像度／カメラ名などの変更は Extension のプロセス再起動（再インストール等）で反映されます。
