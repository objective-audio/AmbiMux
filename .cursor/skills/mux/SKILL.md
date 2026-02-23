---
name: mux
description: Batch convert all .mov videos in workspace/sources/. For each MOV, auto-pairs with a prefix-matching external audio file (.mp4/.wav/.aiff, APAC or LPCM auto-detected) if available, otherwise falls back to embedded HOA LPCM audio (4/9/16ch). Outputs to workspace/export/. Use when the user mentions batch mux, APAC, LPCM, WAV, spatial audio, Vision Pro, workspace folder, embedded audio, or processing multiple MOV files.
---

# AmbiMux: workspace/ の MOV を一括変換（外部オーディオ優先・埋め込みフォールバック）

## 目的

`workspace/sources/` 内の **全 `.mov`** に対し、以下の優先順で変換する:

1. **外部オーディオが見つかった場合** — ファイル名が前方一致するオーディオファイル（`.mp4` / `.wav` / `.aiff`）を使って音声差し替え
2. **外部オーディオが見つからない場合** — `.mov` に埋め込まれた HOA LPCM（4/9/16ch）を APAC にエンコード
3. **どちらも使えない場合** — スキップ（警告表示）

## 前提条件

- **APACエンコーダーはサンドボックス内では動作しない**ため、全てのコマンドは `required_permissions: ["all"]` を指定してサンドボックスなしで実行する

## ワークフロー

### 1) `workspace/sources/` の `.mov` を収集

```bash
find workspace/sources -name "*.mov" -type f | sort
```

### 2) 各 `.mov` に対して処理モードを判定

**Step A: 外部オーディオファイルを探す**

- **優先順位**: `.mp4` → `.wav` → `.aiff`
- **ルール**: `<movのベース名>` で始まるファイルを `workspace/sources/` から探す
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

| チャンネル数         | 結果              |
|----------------------|-------------------|
| 4, 9, 16             | ✅ 埋め込みで変換 |
| その他 / オーディオなし | ❌ スキップ（警告） |

**処理モードの決定まとめ:**

| 外部オーディオ | 埋め込みオーディオ  | 処理                 |
|----------------|---------------------|----------------------|
| あり           | —                   | 外部オーディオで変換 |
| なし           | 4/9/16ch            | 埋め込みで変換       |
| なし           | それ以外 / なし     | スキップ + 警告      |

### 3) ビルド

リポジトリルートで必ずビルドを実行します。

```bash
swift build -c release
```

**ビルド完了の確認:**
- `Build complete!` が出力される
- `.build/release/ambimux` が存在する

### 4) 各 `.mov` に対して変換を実行

**重要**: 全てのコマンドは `required_permissions: ["all"]` を指定してサンドボックスなしで実行します。

**外部オーディオあり（mux-audio 相当）:**

```bash
.build/release/ambimux \
  --audio "workspace/sources/<audio>" \
  --video "workspace/sources/<mov>" \
  --output "workspace/export/<movBaseName>_ambimux.mov"
```

- `--audio` オプションを使用（APAC / LPCM は自動判定）
- APAC ファイルはコピーのみ（再エンコードなし）
- LPCM ファイルは APAC へエンコード

**外部オーディオなし・埋め込みあり（mux-embedded 相当）:**

```bash
.build/release/ambimux \
  --video "workspace/sources/<mov>" \
  --output "workspace/export/<movBaseName>_ambimux.mov"
```

- `--audio` オプションなし（`--video` のみ）
- 埋め込み LPCM から APAC へエンコード
- フォールバックトラックなし（Audio track は APAC の1本のみ）

**出力ファイル名:**
- `<movのベース名>_ambimux.mov`
- 既存ファイルがある場合は自動的にユニーク名が付与される（例: `_1.mov`, `_2.mov`）

### 5) 成功確認（各変換ごと）

**標準出力で確認:**
- `Conversion completed: ...` が出力される
- `Output file verification completed` が出力される

**ファイルの存在確認:**
```bash
ls -lh workspace/export/<output>.mov
```

### 6) 全体サマリを表示

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

### フォルダが無い場合

`workspace/sources/` と `workspace/export/` が無い場合は作成します。

```bash
mkdir -p workspace/sources workspace/export
```

### フォルダ構造

```
workspace/
├── sources/          # 入力ファイル（.mov + オーディオファイル）
└── export/           # 出力ファイル（変換済み .mov）
```

**注意:**
- `workspace/` は `.gitignore` されており、変換用の入出力置き場として使える
- 出力は常に `.mov` 形式

## エラーハンドリング

### `invalidChannelCount`

**原因:**
- 外部オーディオパス: `--audio` ファイルが 4・9・16 チャンネルの LPCM ではない
- 埋め込みパス: 映像ファイルの埋め込みオーディオが 4・9・16 チャンネルではない（`ffprobe` 確認漏れ）

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
