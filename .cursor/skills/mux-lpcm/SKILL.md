---
name: mux-lpcm
description: Batch convert all .mov videos in work/sources/ by auto-pairing each with a prefix-matching LPCM audio file (.wav/.aiff), encode to APAC, then mux into work/export/. Use when the user mentions batch mux with WAV/AIFF, LPCM to APAC conversion, or processing multiple MOV files with uncompressed audio.
---

# AmbiMux: work/ の MOV + LPCM Audio を1本に多重化

## 目的

このリポジトリの `AmbiMux` CLI（`ambimux`）を使い、`work/sources/` 内の **全 `.mov`** に対し、**ファイル名が前方一致する `.wav` または `.aiff`（LPCM音声）** を自動ペアリングして、LPCMからAPACへエンコードし、音声差し替え済みの `.mov` を `work/export/` へ一括変換する。

## 前提

- `work/` は `.gitignore` されており、変換用の入出力置き場として使える（入力は `work/sources/`、出力は `work/export/`）。
- `--lpcm` 入力は **4チャンネル B-format Ambisonics（LPCM）** である必要がある。
- **APACエンコーダーはサンドボックス内では動作しない**ため、全てのコマンドは `required_permissions: ["all"]` を指定してサンドボックスなしで実行する。
- 対応フォーマット: `.wav`, `.aiff`
- 出力は常に `.mov`。既存ファイルがある場合は衝突回避のためユニーク名が付くことがある。

## ワークフロー（全 mov を自動ペアリング→一括変換）

### 1) `work/sources/` の `.mov` を収集

- `work/sources/*.mov` を全て収集する。

### 2) 各 `.mov` に対し、前方一致する `.wav` または `.aiff` をペアリング

各 `.mov` に対して次のルールでオーディオファイルを探す。

- **ルール**: `<movのベース名>` で始まる `.wav` または `.aiff` を `work/sources/` から探す。
- **優先順位**: `.wav` → `.aiff`
- 例: `video_abc.mov` なら `video_abc*.wav` または `video_abc*.aiff`（`video_abc_audio.wav` など）が対象。
- 複数候補がある場合は最初の1つを使う（または警告して全ペアを列挙）。
- ペアが無い `.mov` はスキップして警告。

### 3) ビルド（必要な場合のみ）

`.build/release/ambimux` が無い（または古い）場合のみ、リポジトリルートでビルドする。

```bash
swift build -c release
```

### 4) 各ペアに対して変換を実行（サンドボックスなし）

**重要**: APACエンコーダーはサンドボックス内では動作しないため、`required_permissions: ["all"]` を指定して実行する。

各 `.mov` とペアのオーディオファイルに対し、次のコマンドを実行する。

```bash
.build/release/ambimux \
  --lpcm "work/sources/<audio>" \
  --video "work/sources/<mov>" \
  --output "work/export/<movBaseName>_ambimux.mov"
```

出力名は `<movのベース名>_ambimux.mov` とする。

### 5) 成功確認（各変換ごと）

- 標準出力に次が出ることを確認する。
  - `Conversion completed: ...`
  - `Output file verification completed`
- `work/export/` 内に出力 `.mov` が存在することを確認する。

### 6) 全体サマリを表示

全 `.mov` の処理が終わったら、次を表示する。

- 成功した変換数
- スキップした `.mov`（ペアが無かった）のリスト
- 失敗した変換のリスト（エラーがあれば）

## フォルダが無い場合

`work/sources/` と `work/export/` が無い場合は作成する。

```bash
mkdir -p work/sources work/export
```

## 失敗時の最小切り分け

- **ペアが見つからない**:
  - `.mov` に対して前方一致する `.wav` または `.aiff` が `work/sources/` に無い → スキップして警告。
- `invalidChannelCount`:
  - 入力の `--lpcm` ファイルが4チャンネルではない。4チャンネル B-format Ambisonics のソースを用意する。
- `Cannot Encode` (エラーコード -11834):
  - サンドボックス内で実行された。`required_permissions: ["all"]` を指定してサンドボックスなしで実行する。
- `noAudioTracksFound` / `audioTrackNotFound`:
  - 音声ファイルに音声トラックが無い、または読み取れない。
- `videoTrackNotFound`:
  - 動画ファイルにビデオトラックが無い、または読み取れない。

## ペアリング例

| `.mov`              | 前方一致するオーディオファイル候補                      | ペア結果                                     |
|---------------------|-----------------------------------------------|----------------------------------------------|
| `video_abc.mov`     | `video_abc_audio.wav`                         | ✅ ペア成立                                  |
| `test.mov`          | `test.wav`, `test_spatial.aiff`              | ✅ `test.wav` を使用（.wav優先）             |
| `demo.mov`          | （該当なし）                                  | ❌ スキップ（警告表示）                      |

## 例

具体例は [examples.md](examples.md) を参照。
