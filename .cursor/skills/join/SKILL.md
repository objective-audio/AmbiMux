---
name: join
description: Join all .mov files in workspace/join-input/ in filename order into one MOV using ambimux join (passthrough, no re-encode). Requires at least two inputs with matching video and audio formats (typical use: concatenating mux-output *_ambimux.mov clips). CLI supports optional per-clip trim via path@START-END (seconds). Outputs to workspace/join-output/{first_basename}_joined.mov. Prefer .cursor/skills/join/scripts/batch-join.sh with required_permissions ["all"]. Use when the user mentions join, concatenate, 結合, clip merge, trim ranges, or chaining mux outputs.
---

# AmbiMux: workspace/ の MOV をファイル名順に結合

## 目的

`workspace/join-input/` 内の **全 `.mov`** を **ファイル名順（LC_ALL=C sort）** に並べ、**1本の MOV** に結合する。

- 入力は **2本以上** 必須
- 全クリップの映像・音声フォーマットが一致している必要がある（主用途: `mux-output/` の `*_ambimux.mov` を連結）
- 結合は **パススルー**（再エンコードなし）

## 前提条件

- AVFoundation による書き出しのため、実行は `required_permissions: ["all"]`（サンドボックスなし）とする
- 各入力 MOV には **Ambisonics（4/9/16ch）** の主音声トラックが必要。モノ/ステレオのみのクリップは結合できない

## ワークフロー（batch-join.sh）

結合の本体は **[batch-join.sh](scripts/batch-join.sh)**（リポジトリからは `.cursor/skills/join/scripts/batch-join.sh`）。**毎回 `swift build -c release`**、入力の列挙（`.mov` をファイル名順）、フォーマット検証付き `ambimux join` 呼び出し、終了時の処理サマリまで行う。

1. リポジトリルートからスクリプトを実行する（**必ずサンドボックス外**）。

```bash
.cursor/skills/join/scripts/batch-join.sh
```

## 入力・出力のルール（スクリプトと同じ）

| 項目 | 内容 |
|------|------|
| 入力ディレクトリ | `workspace/join-input/`（デフォルト） |
| 入力列挙 | 直下の全 `.mov` を **ファイル名順** で結合 |
| 最低ファイル数 | **2本以上**。0本・1本はエラー |
| 出力ディレクトリ | `workspace/join-output/`（デフォルト） |
| 出力ファイル名 | **先頭 `.mov` のベース名 + `_joined.mov`**（例: `clip_a.mov` が先頭 → `clip_a_joined.mov`） |
| 結合方式 | `ambimux join` — 映像・音声ともパススルー |
| CLI 区間指定 | `path@START-END`（秒）。バッチは全尺のみ |

## フォルダ構造

```
workspace/
├── join-input/     # 結合する .mov（2本以上）
└── join-output/    # {先頭}_joined.mov
```

`workspace/` は `.gitignore` 想定。出力は常に `.mov`。

## エラーハンドリング

### `concatRequiresAtLeastTwoInputs`

**原因:**
- 入力 `.mov` が1本以下

**対処:**
- `join-input/` に2本以上の互換クリップを置く

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

入力ファイルの組み合わせの参考は [examples.md](examples.md)。全尺の一括結合は **batch-join.sh**、区間付き結合は CLI の `path@START-END` を使う。
