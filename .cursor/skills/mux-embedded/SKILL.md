---
name: mux-embedded
description: Batch convert all .mov videos in work/sources/ that contain embedded HOA LPCM audio (4/9/16ch), encoding it to APAC and muxing into work/export/. Use when the user mentions batch mux without external audio, embedded audio, or processing MOV files that already contain spatial audio tracks.
---

# AmbiMux: work/ の MOV の埋め込みオーディオを HOA として多重化

## 概要

このスキルは [mux-common](../mux-common/SKILL.md) の共通ワークフローを使用します。
以下は埋め込みオーディオ形式固有の設定です。

## 目的

`work/sources/` 内の **全 `.mov`** に対し、映像ファイルに埋め込まれたオーディオトラックを HOA Ambisonics として APAC エンコードし、`work/export/` へ一括変換する。外部オーディオファイルは不要。

## 埋め込みオーディオ固有の前提条件

- 外部オーディオファイルは不要（`--apac` / `--lpcm` オプションは使用しない）
- 映像ファイルの埋め込みオーディオが **4・9・16チャンネルの LPCM** である必要がある
- LPCMからAPACへエンコードする（再エンコード）
- **APACエンコーダーはサンドボックス内では動作しない**ため、全てのコマンドは `required_permissions: ["all"]` を指定してサンドボックスなしで実行する
- 出力にフォールバック（ステレオ）トラックは含まれない

## ペアリングルール（埋め込みオーディオ固有）

外部オーディオファイルとのペアリングは不要。各 `.mov` の埋め込みオーディオのチャンネル数を事前に確認します。

**チャンネル数の確認:**

```bash
ffprobe -v quiet -show_streams -select_streams a "<mov>" 2>&1 | grep channels=
```

**有効なチャンネル数:** 4（1st order）、9（2nd order）、16（3rd order）

**処理可否の判断:**

| チャンネル数 | 結果 |
|---|---|
| 4, 9, 16 | ✅ 変換対象 |
| その他 / オーディオなし | ❌ スキップ（警告表示） |

## 変換コマンド（埋め込みオーディオ固有）

**重要**: APACエンコーダーはサンドボックス内では動作しないため、`required_permissions: ["all"]` を指定して実行します。

```bash
.build/release/ambimux \
  --video "work/sources/<mov>" \
  --output "work/export/<movBaseName>_ambimux.mov"
```

**特徴:**
- `--apac` / `--lpcm` オプションなし（`--video` のみ）
- 埋め込み LPCM から APAC へエンコード（再エンコード）
- **サンドボックスなし（`required_permissions: ["all"]`）で実行必須**
- フォールバックトラックなし（Audio track は APAC の1本のみ）

## 埋め込みオーディオ固有のエラーハンドリング

### `invalidChannelCount`

**原因:**
- 映像ファイルの埋め込みオーディオが 4・9・16チャンネルではない

**対処:**
- `ffprobe` でチャンネル数を確認してスキップ済みのはずだが、確認漏れがあれば再確認

### `noAudioTracksFound`

**原因:**
- 映像ファイルにオーディオトラックが存在しない

**対処:**
- `ffprobe` でオーディオトラックの有無を確認してスキップする

### `Cannot Encode` (エラーコード -11834)

**原因:**
- サンドボックス内で実行された

**対処:**
- `required_permissions: ["all"]` を指定してサンドボックスなしで実行する

## 共通ワークフロー

詳細は [mux-common](../mux-common/SKILL.md) を参照してください:

1. `work/sources/` の `.mov` を収集
2. 各 `.mov` の埋め込みオーディオのチャンネル数を確認（上記の埋め込みオーディオ固有ルール）
3. ビルド（必要な場合のみ）
4. 各 `.mov` に対して変換を実行（上記の埋め込みオーディオ固有コマンド、**サンドボックスなし**）
5. 成功確認
6. 全体サマリを表示
