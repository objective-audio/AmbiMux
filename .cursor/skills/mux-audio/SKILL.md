---
name: mux-audio
description: Batch convert all .mov videos in workspace/sources/ by auto-pairing each with a prefix-matching audio file (.mp4/.wav/.aiff, APAC or LPCM auto-detected), then mux them into workspace/export/. Use when the user mentions batch mux, APAC, LPCM, WAV, spatial audio, Vision Pro, workspace folder, or processing multiple MOV files with an audio file.
---

# AmbiMux: workspace/ の MOV + オーディオファイルを1本に多重化

## 概要

このスキルは [mux-common](../mux-common/SKILL.md) の共通ワークフローを使用します。
以下はオーディオファイル（APAC / LPCM 自動判定）固有の設定です。

## 目的

`workspace/sources/` 内の **全 `.mov`** に対し、**ファイル名が前方一致するオーディオファイル**（`.mp4` / `.wav` / `.aiff`）を自動ペアリングして、音声差し替え済みの `.mov` を `workspace/export/` へ一括変換する。オーディオ形式（APAC / LPCM）は自動判定される。

## 前提条件

- オーディオファイルは **APAC 圧縮済み `.mp4`** または **4チャンネル B-format Ambisonics LPCM**（`.wav` / `.aiff`）のいずれかである必要がある
- 形式は `--audio` オプションにより自動判定される
- LPCM の場合は APAC にエンコードする（再エンコード）
- **APACエンコーダーはサンドボックス内では動作しない**ため、全てのコマンドは `required_permissions: ["all"]` を指定してサンドボックスなしで実行する

## ペアリングルール

各 `.mov` に対して次の優先順位でオーディオファイルを探します。

- **優先順位**: `.mp4` → `.wav` → `.aiff`
- **ルール**: `<movのベース名>` で始まるファイルを `workspace/sources/` から探す
- 例: `video_abc.mov` なら `video_abc*.mp4`、`video_abc*.wav`、`video_abc*.aiff` の順に探す

**ペアリング例:**

| `.mov`              | 候補                                          | ペア結果                                         |
|---------------------|-----------------------------------------------|--------------------------------------------------|
| `video_abc.mov`     | `video_abc_apac00000000.mp4`                  | ✅ `.mp4` を使用                                 |
| `video_abc.mov`     | `video_abc.wav`                               | ✅ `.wav` を使用（`.mp4` がない場合）            |
| `demo.mov`          | `demo.wav`, `demo.aiff`                       | ✅ `.wav` を使用（`.wav` 優先）                  |
| `test.mov`          | （該当なし）                                  | ❌ スキップ（警告表示）                          |

## 変換コマンド

**重要**: APACエンコーダーはサンドボックス内では動作しないため、`required_permissions: ["all"]` を指定して実行します。

```bash
.build/release/ambimux \
  --audio "workspace/sources/<audio>" \
  --video "workspace/sources/<mov>" \
  --output "workspace/export/<movBaseName>_ambimux.mov"
```

**特徴:**
- `--audio` オプションを使用（APAC / LPCM は自動判定）
- APAC ファイルはコピーのみ（再エンコードなし）
- LPCM ファイルは APAC へエンコード（再エンコード）
- **サンドボックスなし（`required_permissions: ["all"]`）で実行必須**

## エラーハンドリング

### `invalidChannelCount`

**原因:**
- 入力の `--audio` ファイルが 4・9・16 チャンネルの LPCM ではない

**対処:**
- 4チャンネル B-format Ambisonics のソースを用意する
- チャンネル数を確認: `ffprobe -v error -show_streams -select_streams a <file>`

### `noAudioTracksFound`

**原因:**
- 音声ファイルに音声トラックが存在しない

**対処:**
- ファイルが正しいオーディオファイルか確認する

### `Cannot Encode` (エラーコード -11834)

**原因:**
- サンドボックス内で実行された

**対処:**
- `required_permissions: ["all"]` を指定してサンドボックスなしで実行する

## 共通ワークフロー

詳細は [mux-common](../mux-common/SKILL.md) を参照してください:

1. `workspace/sources/` の `.mov` を収集
2. 各 `.mov` に対してオーディオファイルをペアリング（上記のペアリングルール）
3. ビルド（必要な場合のみ）
4. 各ペアに対して変換を実行（上記のコマンド、**サンドボックスなし**）
5. 成功確認
6. 全体サマリを表示

## 例

具体例は [examples.md](examples.md) を参照。
