---
name: join
description: Join MOV clips via batch-join.sh — either all .mov in workspace/join-input/ (filename order, full length) or segments listed in join-input/join.txt (line order, optional path@START-END seconds). A single segment with @START-END trims without concatenating. Passthrough, no re-encode; matching video/audio formats required when joining two or more. Outputs to workspace/join-output/{first_basename}_joined.mov. Prefer .cursor/skills/join/scripts/batch-join.sh with required_permissions ["all"]. Use when the user mentions join, concatenate, 結合, clip merge, trim ranges, join.txt, or chaining mux outputs.
---

# AmbiMux: workspace/ の MOV を結合

## 目的

`workspace/join-input/` のクリップを **1本の MOV** に結合する。

- 入力は **1セグメント以上**（0件はエラー）。1セグメントは全尺コピーまたは `@START-END` による切り出し
- 2セグメント以上のとき、全クリップの映像・音声フォーマットが一致している必要がある（主用途: `mux-output/` の `*_ambimux.mov` を連結）
- 結合は **パススルー**（再エンコードなし）

## 前提条件

- AVFoundation による書き出しのため、実行は `required_permissions: ["all"]`（サンドボックスなし）とする
- 各入力 MOV には **Ambisonics（4/9/16ch）** の主音声トラックが必要。モノ/ステレオのみのクリップは結合できない

## ワークフロー（batch-join.sh）

結合の本体は **[batch-join.sh](scripts/batch-join.sh)**（リポジトリからは `.cursor/skills/join/scripts/batch-join.sh`）。**毎回 `swift build -c release`**、入力の列挙または `join.txt` 解釈、フォーマット検証付き `ambimux join` 呼び出し、終了時の処理サマリまで行う。

1. リポジトリルートからスクリプトを実行する（**必ずサンドボックス外**）。

```bash
.cursor/skills/join/scripts/batch-join.sh
```

バックグラウンド起動してよい。**完了条件**は次の両方:

- stdout に `BATCH_JOIN_DONE exit=` が出ている
- シェルプロセスが終了している

`exit=0` ならサマリを成功としてユーザーへ報告する。非0なら失敗サマリをそのまま報告する。

**完了にしない:** `Joining` / `Output:` / `swift build` / `Join completed:` 単体。`Join completed:` のあとにスクリプトがサマリを出し、exit code が確定するまでがジョブ全体。

## 入力・出力のルール（スクリプトと同じ）

| 項目 | 内容 |
|------|------|
| 入力ディレクトリ | `workspace/join-input/`（デフォルト） |
| マニフェストあり | `join-input/join.txt` がある → **行順**で結合。区間は `file.mov@START-END`（秒）。未記載の `.mov` は無視 |
| マニフェストなし | 直下の全 `.mov` を **ファイル名順・全尺** で結合 |
| 最低セグメント数 | **1以上**。0 はエラー。1行の `@START-END` は切り出し |
| 出力ディレクトリ | `workspace/join-output/`（デフォルト） |
| 出力ファイル名 | **先頭セグメントのベース名 + `_joined.mov`** |
| 結合方式 | `ambimux join` — 映像・音声ともパススルー |
| CLI 区間指定 | 手動実行時も同じ `path@START-END`（秒） |

### `join.txt` の書式

```text
# コメントと空行は無視
clip_a.mov@1.5-12.0
clip_b.mov@0-8.0
clip_c.mov
```

- 1行 = 1セグメント（入力ディレクトリ直下の **ベース名のみ**）
- `@` 無し → 全尺。1行だけなら切り出し（または全尺コピー）。同じファイルを複数行書いて複数区間をつなげてよい
- ファイル名に空白・サブディレクトリは不可

## フォルダ構造

```
workspace/
├── join-input/     # 結合または切り出す .mov（1本以上）+ 任意で join.txt
└── join-output/    # {先頭}_joined.mov
```

`workspace/` は `.gitignore` 想定。出力は常に `.mov`。

## エラーハンドリング

### `concatRequiresAtLeastOneInput`

**原因:**
- 入力セグメントが0件（走査結果または `join.txt`）

**対処:**
- `join-input/` に `.mov` を置く、または `join.txt` に1行以上書く

### `concatFormatMismatch`

**原因:**
- クリップ間で映像コーデック・解像度・フレームレート、または音声トラック数・フォーマットが一致しない
- 例: APAC 出力と LPCM 出力の混在

**対処:**
- すべて同じ mux 設定（`--audio-output apac` 等）で出力したクリップを使う
- `ffprobe -v error -show_streams <file>` で各クリップのストリームを比較

### `concatCompositionFailed`

**原因:**
- フォーマット検証後の composition / 書き出し段階で失敗

**対処:**
- 入力ファイルが破損していないか確認
- ディスク容量・書き込み権限を確認

### `noAmbisonicsTrackFound` / `noAudioTracksFound`

**原因:**
- 入力 MOV に Ambisonics 主トラックがない、または音声トラックが読み取れない

**対処:**
- 先に mux スキルで APAC 空間音声を mux したクリップを使う

### `videoTrackNotFound`

**原因:**
- 入力 MOV にビデオトラックがない

**対処:**
- ファイルが破損していないか、正しい MOV か確認

### `concatInvalidTimeRange` / `concatInvalidSegmentArgument`

**原因:**
- `@START-END` の値が不正（`start >= end`、負値）、またはソース尺を超えている

**対処:**
- 秒単位で `start < end` かつクリップ尺内になるよう指定する（例: `clip.mov@1.5-12.0`）

### `invalidChannelCount`

**原因:**
- Ambisonics でもモノ/ステレオでもないチャンネル数の音声トラックがある

**対処:**
- 4・9・16ch Ambisonics + 任意の 1/2ch フォールバック構成に揃える

## 例

入力ファイルの組み合わせの参考は [examples.md](examples.md)。実行は **batch-join.sh**（全尺走査または `join.txt`）。区間付きの手動実行は CLI の `path@START-END` も可。
