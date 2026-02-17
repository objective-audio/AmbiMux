---
name: mux-common
description: Common workflow and utilities for batch audio muxing with AmbiMux. This is a base skill referenced by format-specific skills like mux-apac and mux-lpcm. Not intended to be used directly.
---

# AmbiMux: 共通ワークフローとユーティリティ

このスキルは、`mux-apac`、`mux-lpcm`などの形式固有スキルから参照される共通部分を定義します。
このスキルを直接使用せず、形式固有のスキルを使用してください。

## 共通ワークフロー

### 1) `work/sources/` の `.mov` を収集

`work/sources/` ディレクトリ内の全ての `.mov` ファイルを収集します。

```bash
find work/sources -name "*.mov" -type f | sort
```

### 2) 各 `.mov` に対してオーディオファイルをペアリング

各 `.mov` ファイルに対して、ファイル名が前方一致するオーディオファイルを探します。

**ペアリングの基本ルール:**
- `<movのベース名>` で始まるオーディオファイルを `work/sources/` から探す
- 例: `video_abc.mov` のベース名は `video_abc`
- 前方一致: `video_abc*.{拡張子}` がマッチ
  - `video_abc.wav` ✅
  - `video_abc_audio.mp4` ✅
  - `video_abc_apac00000000.mp4` ✅
  - `video.wav` ❌（前方一致しない）

**複数候補がある場合:**
- 最初に見つかった1つを使用
- または警告して全ペアを列挙

**ペアが無い場合:**
- その `.mov` をスキップ
- 警告を表示

### 3) ビルド（必要な場合のみ）

`.build/release/ambimux` が無い（または古い）場合のみ、リポジトリルートでビルドします。

```bash
swift build -c release
```

**ビルドの確認:**
```bash
test -f .build/release/ambimux && echo "exists" || echo "not found"
```

### 4) 各ペアに対して変換を実行

形式固有のスキルで実装されます。
- `mux-apac`: `--apac` オプションを使用
- `mux-lpcm`: `--lpcm` オプションを使用（サンドボックスなし）

**基本コマンド形式:**
```bash
.build/release/ambimux \
  --{apac|lpcm} "work/sources/<audio>" \
  --video "work/sources/<mov>" \
  --output "work/export/<movBaseName>_ambimux.mov"
```

**出力ファイル名:**
- `<movのベース名>_ambimux.mov`
- 既存ファイルがある場合は自動的にユニーク名が付与される（例: `_1.mov`, `_2.mov`）

### 5) 成功確認（各変換ごと）

各変換の成功を確認します。

**標準出力で確認:**
- `Conversion completed: ...` が出力される
- `Output file verification completed` が出力される

**ファイルの存在確認:**
```bash
ls -lh work/export/<output>.mov
```

**出力内容の確認:**
- ファイルサイズが0より大きい
- Audio track 1: 4チャンネル APAC (Ambisonics)
- Audio track 2: 2チャンネル ステレオフォールバック（元動画から）

### 6) 全体サマリを表示

全ての `.mov` の処理が終わったら、以下を表示します。

**サマリフォーマット:**
```
## 処理結果サマリ

### 検出されたファイル
- `.mov`ファイル: X件

### 変換結果
- ✅ 成功した変換: Y件
- ❌ スキップした`.mov`: Z件
- ❌ 失敗した変換: W件

### 統計
- 成功: Y件
- スキップ: Z件（ペアが無かった）
- 失敗: W件
```

**スキップしたファイルのリスト:**
```
スキップした`.mov`:
- filename1.mov (理由: ペアが見つからない)
- filename2.mov (理由: ペアが見つからない)
```

**失敗したファイルのリスト:**
```
失敗した変換:
- filename3.mov (エラー: Cannot Encode)
```

## フォルダ管理

### フォルダが無い場合

`work/sources/` と `work/export/` が無い場合は作成します。

```bash
mkdir -p work/sources work/export
```

### フォルダ構造

```
work/
├── sources/          # 入力ファイル（.mov + オーディオファイル）
└── export/           # 出力ファイル（変換済み .mov）
```

**注意:**
- `work/` は `.gitignore` されており、変換用の入出力置き場として使える
- 出力は常に `.mov` 形式

## 共通エラーハンドリング

### ペアリングエラー

**ペアが見つからない:**
- `.mov` に対して前方一致するオーディオファイルが `work/sources/` に無い
- 対処: スキップして警告を表示

### オーディオトラックエラー

**`noAudioTracksFound` / `audioTrackNotFound`:**
- 音声ファイルに音声トラックが無い、または読み取れない
- 対処: 
  - ファイルが破損していないか確認
  - 正しい形式のオーディオファイルか確認

### ビデオトラックエラー

**`videoTrackNotFound`:**
- 動画ファイルにビデオトラックが無い、または読み取れない
- 対処:
  - ファイルが破損していないか確認
  - 正しい形式の動画ファイルか確認

## 形式固有のスキル

このスキルは以下の形式固有スキルから参照されます:

- **[mux-apac](../mux-apac/SKILL.md)**: APAC圧縮済みMP4ファイルを使用
- **[mux-lpcm](../mux-lpcm/SKILL.md)**: LPCM非圧縮WAV/AIFFファイルを使用

各スキルは、このスキルの共通ワークフローに加えて、形式固有の設定とエラーハンドリングを提供します。
