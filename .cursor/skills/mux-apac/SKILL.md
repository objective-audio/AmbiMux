---
name: mux-apac
description: Batch convert all .mov videos in work/sources/ by auto-pairing each with a prefix-matching APAC .mp4 audio file, then mux them into work/export/. Use when the user mentions batch mux, ambimux, APAC, spatial audio, Vision Pro, work folder, or processing multiple MOV files.
---

# AmbiMux: work/ の MOV + APAC MP4 を1本に多重化

## 目的

このリポジトリの `AmbiMux` CLI（`ambimux`）を使い、`work/sources/` 内の **全 `.mov`** に対し、**ファイル名が前方一致する `.mp4`（APAC音声）** を自動ペアリングして、音声差し替え済みの `.mov` を `work/export/` へ一括変換する。

## 前提

- `work/` は `.gitignore` されており、変換用の入出力置き場として使える（入力は `work/sources/`、出力は `work/export/`）。
- `--apac` 入力は **APAC** である必要がある（APACでない場合は `expectedAPACAudio` が発生）。
- 出力は常に `.mov`。既存ファイルがある場合は衝突回避のためユニーク名が付くことがある。

## ワークフロー（全 mov を自動ペアリング→一括変換）

### 1) `work/sources/` の `.mov` を収集

- `work/sources/*.mov` を全て収集する。

### 2) 各 `.mov` に対し、前方一致する `.mp4` をペアリング

各 `.mov` に対して次のルールで `.mp4` を探す。

- **ルール**: `<movのベース名>` で始まる `.mp4` を `work/sources/` から探す。
- 例: `video_abc.mov` なら `video_abc*.mp4`（`video_abc_apac00000000.mp4` など）が対象。
- 複数候補がある場合は最初の1つを使う（または警告して全ペアを列挙）。
- ペアが無い `.mov` はスキップして警告。

### 3) ビルド（必要な場合のみ）

`.build/release/ambimux` が無い（または古い）場合のみ、リポジトリルートでビルドする。

```bash
swift build -c release
```

### 4) 各ペアに対して変換を実行

各 `.mov` とペアの `.mp4` に対し、次のコマンドを実行する。

```bash
.build/release/ambimux \
  --apac "work/sources/<movBaseName>_*.mp4" \
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
  - `.mov` に対して前方一致する `.mp4` が `work/sources/` に無い → スキップして警告。
- `expectedAPACAudio`:
  - 入力の `--apac` mp4 がAPACではない。`--apac` ではコピーできないため、APACのソースを用意するか、別フロー（例: `--lpcm`）を検討する。
- `noAudioTracksFound` / `audioTrackNotFound`:
  - 音声ファイルに音声トラックが無い、または読み取れない。
- `videoTrackNotFound`:
  - 動画ファイルにビデオトラックが無い、または読み取れない。

## ペアリング例

| `.mov`              | 前方一致する `.mp4` 候補                      | ペア結果                                     |
|---------------------|-----------------------------------------------|----------------------------------------------|
| `video_abc.mov`     | `video_abc_apac00000000.mp4`                  | ✅ ペア成立                                  |
| `test.mov`          | `test_audio.mp4`, `test2.mp4`                | ✅ `test_audio.mp4` を使用（最初の候補）     |
| `demo.mov`          | （該当なし）                                  | ❌ スキップ（警告表示）                      |

## 例

具体例は [examples.md](examples.md) を参照。
