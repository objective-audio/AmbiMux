---
name: mux
description: Batch convert all .mov videos in workspace/mux-input/. For each MOV, auto-pairs with a prefix-matching external audio file (.mp4/.wav/.aiff, APAC or LPCM auto-detected) if available, otherwise uses embedded Ambisonics (4/9/16ch) only when the first audio track qualifies. Primary spatial audio is output as APAC; mono/stereo is searched across all embedded tracks and passed through as a second audio track when present. Outputs to workspace/output/. Use when the user mentions batch mux, APAC, LPCM, WAV, spatial audio, Vision Pro, workspace folder, embedded audio, or processing multiple MOV files.
---

# AmbiMux: workspace/ の MOV を一括変換（外部オーディオ優先・埋め込みフォールバック）

## 目的

`workspace/mux-input/` 内の **全 `.mov`** に対し、以下の優先順で変換する:

1. **外部オーディオが見つかった場合** — ファイル名が前方一致するオーディオファイル（`.mp4` / `.wav` / `.aiff`）を使って音声差し替え
2. **外部オーディオが見つからない場合** — `.mov` の **先頭の音声トラック**が **Ambisonics（4/9/16ch）** ならそれを主として **APAC** で出力。**モノ/ステレオ（1/2ch）** は全トラックから探し、見つかれば **第2トラックとしてパススルー** で含める
3. **どちらも使えない場合** — スキップ（警告表示）

## 前提条件

- **APACエンコーダーはサンドボックス内では動作しない**ため、全てのコマンドは `required_permissions: ["all"]` を指定してサンドボックスなしで実行する

## ワークフロー

### 1) フォルダ準備

`workspace/mux-input/` と `workspace/output/` が無い場合は作成する。

```bash
mkdir -p workspace/mux-input workspace/output
```

### 2) 【必須】ビルド — 省略してはならない

**ビルドは絶対に省略しない。** 以下のいずれの場合でも、毎回必ず実行する:

- `.mov` が0件でも実行する
- 既存の `.build/release/ambimux` があっても実行する
- 変換対象が1件もない場合でも実行する

リポジトリルートでビルドを実行する。`required_permissions: ["all"]` を指定してサンドボックスなしで実行する。

```bash
swift build -c release
```

**ビルド完了の確認:**
- `Build complete!` が出力される
- `.build/release/ambimux` が存在する

### 3) `workspace/mux-input/` の `.mov` を収集

```bash
find workspace/mux-input -name "*.mov" -type f | sort
```

### 4) 各 `.mov` に対して処理モードを判定

**Step A: 外部オーディオファイルを探す**

- **優先順位**: `.mp4` → `.wav` → `.aiff`
- **ルール**: `<movのベース名>` で始まるファイルを `workspace/mux-input/` から探す
- 例: `video_abc.mov` なら `video_abc*.mp4`、`video_abc*.wav`、`video_abc*.aiff` の順に探す

**ペアリング例:**

| `.mov`          | 候補                         | ペア結果                          |
|-----------------|------------------------------|-----------------------------------|
| `video_abc.mov` | `video_abc_apac00000000.mp4` | ✅ `.mp4` を使用                  |
| `video_abc.mov` | `video_abc.wav`              | ✅ `.wav` を使用（`.mp4` がない場合） |
| `demo.mov`      | `demo.wav`, `demo.aiff`      | ✅ `.wav` を使用（`.wav` 優先）   |
| `test.mov`      | （該当なし）                 | → Step B へ                       |

**Step B: 外部オーディオが無い場合 — 埋め込みオーディオを確認**

```bash
ffprobe -v quiet -show_streams -select_streams a "<mov>" 2>&1 | grep channels=
```

| 条件 | 結果 |
|------|------|
| **先頭の**音声トラックが 4 / 9 / 16ch（Ambisonics として解釈可能） | ✅ 埋め込みで変換（主トラック）。他トラックに 1/2ch があれば出力に第2音声として追加 |
| 先頭トラックが Ambisonics でない、またはオーディオなし | ❌ スキップ（警告） |

`ffprobe` では複数行の `channels=` が出ることがあります。埋め込み主トラックの判定は **先頭の音声ストリームのチャンネル数**に基づきます（2本目以降にだけ 4/9/16ch があっても対象外）。

**処理モードの決定まとめ:**

| 外部オーディオ | 埋め込みオーディオ  | 処理                 |
|----------------|---------------------|----------------------|
| あり           | —                   | 外部オーディオで変換 |
| なし           | **先頭**トラックが Ambisonics（4/9/16ch） | 埋め込みで変換（モノ/ステレオの別トラックがあれば第2トラックも出力） |
| なし           | 先頭が Ambisonics でない / オーディオなし | スキップ + 警告      |

### 5) 各 `.mov` に対して変換を実行

**前提条件:** 必ず 2) ビルドが成功してから変換を実行する。ビルド未実行・失敗の場合は変換に進まない。

**重要**: 全てのコマンドは `required_permissions: ["all"]` を指定してサンドボックスなしで実行します。

**外部オーディオあり（mux-audio 相当）:**

```bash
.build/release/ambimux \
  --audio "workspace/mux-input/<audio>" \
  --video "workspace/mux-input/<mov>" \
  --output "workspace/output/<movBaseName>_ambimux.mov" \
  --audio-output apac
```

- `--audio` オプションを使用（APAC / LPCM は自動判定）
- APAC ファイルはコピーのみ（再エンコードなし）
- LPCM ファイルは **APAC** へエンコードして出力
- 映像 `.mov` に **モノ/ステレオ（1/2ch）** の埋め込みトラックがある場合、主トラック（外部 Ambisonics 由来の APAC）に加えて **第2音声トラックとしてパススルー**（フォールバック）する

**外部オーディオなし・埋め込みあり（mux-embedded 相当）:**

```bash
.build/release/ambimux \
  --video "workspace/mux-input/<mov>" \
  --output "workspace/output/<movBaseName>_ambimux.mov" \
  --audio-output apac
```

- `--audio` オプションなし（`--video` のみ）
- **主トラック**: **先頭の**埋め込み Ambisonics を **APAC** で出力（LPCM → APAC エンコード、埋め込みが APAC ならコピー）
- **第2トラック（任意）**: 同一 `.mov` 内に **モノ/ステレオ（1/2ch）** の音声トラックもあれば、**フォールバック用としてそのフォーマットのままパススルー**し、出力の音声トラックは **最大2本**（主 Ambisonics + フォールバック）になる

**出力ファイル名:**
- `<movのベース名>_ambimux.mov`
- 既存ファイルがある場合は自動的にユニーク名が付与される（例: `_1.mov`, `_2.mov`）

**出力オーディオフォーマット（本スキルでは常に `--audio-output apac` を指定）:**

| 入力（主・Ambisonics） | 主トラック出力 |
|------------------------|----------------|
| APAC | APAC（コピー） |
| LPCM | APAC（エンコード） |

映像内のモノ/ステレオは上表の対象外で、検出された場合は **元のコーデックのまま** 第2トラックに追加される。

### 6) 成功確認（各変換ごと）

**標準出力で確認:**
- `Conversion completed: ...` が出力される
- `Output file verification completed` が出力される

**ファイルの存在確認:**
```bash
ls -lh workspace/output/<output>.mov
```

### 7) 全体サマリを表示

全ての `.mov` の処理が終わったら、以下を表示します。

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
- スキップ: Z件
- 失敗: W件
```

**スキップしたファイルのリスト:**
```
スキップした`.mov`:
- filename1.mov (理由: 外部オーディオなし・埋め込みオーディオも対象外)
```

**失敗したファイルのリスト:**
```
失敗した変換:
- filename2.mov (エラー: Cannot Encode)
```

## フォルダ管理

フォルダ作成はワークフローの 1) で行う。

### フォルダ構造

```
workspace/
├── mux-input/        # 入力ファイル（.mov + オーディオファイル）
└── output/           # 出力ファイル（変換済み .mov）
```

**注意:**
- `workspace/` は `.gitignore` されており、変換用の入出力置き場として使える
- 出力は常に `.mov` 形式

## エラーハンドリング

### `invalidChannelCount`

**原因:**
- 外部オーディオパス: `--audio` ファイルが 4・9・16 チャンネルの LPCM ではない
- 埋め込みパス: **先頭の音声トラック**が **4・9・16 チャンネルの Ambisonics** でない（2本目以降にだけ Ambisonics があっても対象外）。モノ/ステレオだけでは主トラックを構成できない

**対処:**
- チャンネル数を確認: `ffprobe -v error -show_streams -select_streams a <file>`

### `noAudioTracksFound` / `audioTrackNotFound`

**原因:**
- 音声ファイルに音声トラックが無い、または読み取れない

**対処:**
- ファイルが破損していないか確認
- 正しい形式のオーディオファイルか確認

### `videoTrackNotFound`

**原因:**
- 動画ファイルにビデオトラックが無い、または読み取れない

**対処:**
- ファイルが破損していないか確認
- 正しい形式の動画ファイルか確認

### `Cannot Encode` (エラーコード -11834)

**原因:**
- サンドボックス内で実行された

**対処:**
- `required_permissions: ["all"]` を指定してサンドボックスなしで実行する

## 例

具体例は [examples.md](examples.md) を参照。
