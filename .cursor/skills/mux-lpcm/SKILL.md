---
name: mux-lpcm
description: Batch convert all .mov videos in work/sources/ by auto-pairing each with a prefix-matching LPCM audio file (.wav/.aiff), encode to APAC, then mux into work/export/. Use when the user mentions batch mux with WAV/AIFF, LPCM to APAC conversion, or processing multiple MOV files with uncompressed audio.
---

# AmbiMux: work/ の MOV + LPCM Audio を1本に多重化

## 概要

このスキルは [mux-common](../mux-common/SKILL.md) の共通ワークフローを使用します。
以下はLPCM形式固有の設定です。

## 目的

`work/sources/` 内の **全 `.mov`** に対し、**ファイル名が前方一致する `.wav` または `.aiff`（LPCM音声）** を自動ペアリングして、LPCMからAPACへエンコードし、音声差し替え済みの `.mov` を `work/export/` へ一括変換する。

## LPCM固有の前提条件

- `--audio` で指定したファイルは **4チャンネル B-format Ambisonics（LPCM）** である必要がある
- LPCMからAPACへエンコードする（再エンコード）
- **APACエンコーダーはサンドボックス内では動作しない**ため、全てのコマンドは `required_permissions: ["all"]` を指定してサンドボックスなしで実行する
- 対応フォーマット: `.wav`, `.aiff`

## ペアリングルール（LPCM固有）

各 `.mov` に対して次のルールでオーディオファイルを探します。

- **ルール**: `<movのベース名>` で始まる `.wav` または `.aiff` を `work/sources/` から探す
- **対象拡張子**: `.wav`, `.aiff`
- **優先順位**: `.wav` → `.aiff`
- 例: `video_abc.mov` なら `video_abc*.wav` または `video_abc*.aiff`（`video_abc_audio.wav` など）が対象

**ペアリング例:**

| `.mov`              | 前方一致するオーディオファイル候補                      | ペア結果                                     |
|---------------------|-----------------------------------------------|----------------------------------------------|
| `video_abc.mov`     | `video_abc_audio.wav`                         | ✅ ペア成立                                  |
| `test.mov`          | `test.wav`, `test_spatial.aiff`              | ✅ `test.wav` を使用（.wav優先）             |
| `demo.mov`          | （該当なし）                                  | ❌ スキップ（警告表示）                      |

## 変換コマンド（LPCM固有）

**重要**: APACエンコーダーはサンドボックス内では動作しないため、`required_permissions: ["all"]` を指定して実行します。

```bash
.build/release/ambimux \
  --audio "work/sources/<audio>.wav" \
  --video "work/sources/<mov>" \
  --output "work/export/<movBaseName>_ambimux.mov"
```

**特徴:**
- `--audio` オプションを使用（APAC/LPCM は自動判定）
- LPCMからAPACへエンコード（再エンコード）
- **サンドボックスなし（`required_permissions: ["all"]`）で実行必須**

## LPCM固有のエラーハンドリング

### `invalidChannelCount`

**原因:**
- 入力の `--audio` ファイルが4チャンネルではない

**対処:**
- 4チャンネル B-format Ambisonics のソースを用意する
- チャンネル数を確認: `ffprobe -v error -show_streams -select_streams a <file>`

### `Cannot Encode` (エラーコード -11834)

**原因:**
- サンドボックス内で実行された
- APACエンコーダーがサンドボックス内では動作しない

**対処:**
- `required_permissions: ["all"]` を指定してサンドボックスなしで実行する
- コマンド実行時に権限を要求される場合は承認する

## 共通ワークフロー

詳細は [mux-common](../mux-common/SKILL.md) を参照してください:

1. `work/sources/` の `.mov` を収集
2. 各 `.mov` に対してオーディオファイルをペアリング（上記のLPCM固有ルール）
3. ビルド（必要な場合のみ）
4. 各ペアに対して変換を実行（上記のLPCM固有コマンド、**サンドボックスなし**）
5. 成功確認
6. 全体サマリを表示

## 例

具体例は [examples.md](examples.md) を参照。
