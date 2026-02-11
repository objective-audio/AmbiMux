---
name: mux-apac
description: Mux or replace APAC (Apple Positional Audio Codec) spatial audio from an .mp4 into a .mov video using AmbiMux, reading inputs from work/sources/ and writing the output .mov to work/export/. Use when the user mentions ambimux, APAC, spatial audio, Vision Pro, work folder, mux, embedding, or replacing audio in MOV.
---

# AmbiMux: work/ の MOV + APAC MP4 を1本に多重化

## 目的

このリポジトリの `AmbiMux` CLI（`ambimux`）を使い、`work/sources/` 内の **映像（.mov）** と **APAC音声（.mp4）** を入力にして、音声差し替え済みの **1本の `.mov`** を `work/export/` に書き出す。

## 前提

- `work/` は `.gitignore` されており、変換用の入出力置き場として使える（入力は `work/sources/`、出力は `work/export/`）。
- `--apac` 入力は **APAC** である必要がある（APACでない場合は `expectedAPACAudio` が発生）。
- 出力は常に `.mov`。既存ファイルがある場合は衝突回避のためユニーク名が付くことがある。

## ワークフロー（毎回、入力を選ばせる）

### 1) `work/sources/` の候補を収集

- `work/sources/` を一覧して、候補ファイルを集める。
  - **video候補**: `*.mov`（必要なら `*.mp4` も候補に含めてよい）
  - **audio候補**: `*.mp4`（APACを想定）

候補が1つずつに確定できない場合は、ユーザーに選択させる。

### 2) ユーザーに video / audio を選ばせる

`AskQuestion` を使い、次を1つずつ選択させる。

- **video**: 変換対象の動画（例: `work/xxxx.mov`）
- **audio**: 付けたいAPAC音声（例: `work/xxxx.mp4`）

### 3) ビルド（必要な場合のみ）

`.build/release/ambimux` が無い（または古い）場合のみ、リポジトリルートでビルドする。

```bash
swift build -c release
```

### 4) 出力パスを決める（上書き防止で `--output` を明示）

デフォルトは次を推奨する。

- `work/export/<videoBaseName>_ambimux.mov`

例: `work/export/video_ambimux.mov`

### 5) 変換コマンドを実行

```bash
.build/release/ambimux \
  --apac "work/sources/<audio>.mp4" \
  --video "work/sources/<video>.mov" \
  --output "work/export/<videoBaseName>_ambimux.mov"
```

### 6) 成功確認

- 標準出力に次が出ることを確認する。
  - `Conversion completed: ...`
  - `Output file verification completed`
- `work/export/` 内に出力 `.mov` が存在することを確認する。

## フォルダが無い場合

`work/sources/` と `work/export/` が無い場合は作成する。

```bash
mkdir -p work/sources work/export
```

## 失敗時の最小切り分け

- `expectedAPACAudio`:
  - 入力の `--apac` mp4 がAPACではない。`--apac` ではコピーできないため、APACのソースを用意するか、別フロー（例: `--lpcm`）を検討する。
- `noAudioTracksFound` / `audioTrackNotFound`:
  - 音声ファイルに音声トラックが無い、または読み取れない。
- `videoTrackNotFound`:
  - 動画ファイルにビデオトラックが無い、または読み取れない。

## 例

具体例は [examples.md](examples.md) を参照。
