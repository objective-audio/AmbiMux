---
name: mux-apac
description: Batch convert all .mov videos in work/sources/ by auto-pairing each with a prefix-matching APAC .mp4 audio file, then mux them into work/export/. Use when the user mentions batch mux, ambimux, APAC, spatial audio, Vision Pro, work folder, or processing multiple MOV files.
---

# AmbiMux: work/ の MOV + APAC MP4 を1本に多重化

## 概要

このスキルは [mux-common](../mux-common/SKILL.md) の共通ワークフローを使用します。
以下はAPAC形式固有の設定です。

## 目的

`work/sources/` 内の **全 `.mov`** に対し、**ファイル名が前方一致する `.mp4`（APAC音声）** を自動ペアリングして、音声差し替え済みの `.mov` を `work/export/` へ一括変換する。

## APAC固有の前提条件

- `--audio` で指定したファイルが **APAC圧縮済み** である必要がある（APACでない場合は `expectedAPACAudio` が発生）
- APACファイルはコピーのみで再エンコードしない
- サンドボックス内で実行可能

## ペアリングルール（APAC固有）

各 `.mov` に対して次のルールで `.mp4` を探します。

- **ルール**: `<movのベース名>` で始まる `.mp4` を `work/sources/` から探す
- **対象拡張子**: `.mp4` のみ
- 例: `video_abc.mov` なら `video_abc*.mp4`（`video_abc_apac00000000.mp4` など）が対象

**ペアリング例:**

| `.mov`              | 前方一致する `.mp4` 候補                      | ペア結果                                     |
|---------------------|-----------------------------------------------|----------------------------------------------|
| `video_abc.mov`     | `video_abc_apac00000000.mp4`                  | ✅ ペア成立                                  |
| `test.mov`          | `test_audio.mp4`, `test2.mp4`                | ✅ `test_audio.mp4` を使用（最初の候補）     |
| `demo.mov`          | （該当なし）                                  | ❌ スキップ（警告表示）                      |

## 変換コマンド（APAC固有）

```bash
.build/release/ambimux \
  --audio "work/sources/<audio>.mp4" \
  --video "work/sources/<mov>" \
  --output "work/export/<movBaseName>_ambimux.mov"
```

**特徴:**
- `--audio` オプションを使用（APAC/LPCM は自動判定）
- APACファイルはコピーのみ（再エンコードなし）
- サンドボックス内で実行可能

## APAC固有のエラーハンドリング

### `expectedAPACAudio`

**原因:**
- 入力の `--audio` mp4 がAPAC形式ではない

**対処:**
- APACエンコード済みのソースを用意する
- または `mux-lpcm` スキルを使用してLPCMから変換する

## 共通ワークフロー

詳細は [mux-common](../mux-common/SKILL.md) を参照してください:

1. `work/sources/` の `.mov` を収集
2. 各 `.mov` に対してオーディオファイルをペアリング（上記のAPAC固有ルール）
3. ビルド（必要な場合のみ）
4. 各ペアに対して変換を実行（上記のAPAC固有コマンド）
5. 成功確認
6. 全体サマリを表示

## 例

具体例は [examples.md](examples.md) を参照。
