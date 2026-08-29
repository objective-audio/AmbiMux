---
name: attenuate
description: Batch-lower APAC Ambisonics level in MOVs via batch-attenuate.sh. Requires workspace/attenuate-input/attenuate.txt (basename.mov@DB; DB is --db, 0 or positive). Only listed files are processed; unlisted .mov are ignored. Outputs workspace/attenuate-output/{base}_attenuated.mov. Prefer .cursor/skills/attenuate/scripts/batch-attenuate.sh with required_permissions ["all"]. Use when the user mentions attenuate, 減衰, レベル調整, attenuate.txt, attenuate-input, or batch level lowering of APAC MOV files.
---

# AmbiMux: workspace/ の MOV を一括減衰

## 目的

`workspace/attenuate-input/` のクリップを **ファイルごとに指定した dB** で減衰し、`workspace/attenuate-output/` に書き出す。

- **`attenuate.txt` 必須**。無い、または有効行が 0 はエラー
- 未記載の `.mov` は無視
- 映像はパススルー。APAC Ambisonics はデコード → ゲイン → 再エンコード（`--db` がほぼ 0 のときはコピー）
- **ブースト禁止**（`@` の値は CLI の `--db` と同じ下げ幅で、0 以上）

## 前提条件

- **APACエンコーダーはサンドボックス内では動作しない**ため、実行は `required_permissions: ["all"]`（サンドボックスなし）とする
- 各入力 MOV には **APAC の Ambisonics（4/9/16ch）** 主トラックが必要。LPCM のままでは減衰できない

## ワークフロー（batch-attenuate.sh）

減衰の本体は **[batch-attenuate.sh](scripts/batch-attenuate.sh)**（リポジトリからは `.cursor/skills/attenuate/scripts/batch-attenuate.sh`）。**毎回 `swift build -c release`**、`attenuate.txt` 解釈、各行への `ambimux attenuate` 呼び出し、終了時の処理サマリまで行う。1本失敗しても残りは続ける。

1. リポジトリルートからスクリプトを実行する（**必ずサンドボックス外**）。

```bash
.cursor/skills/attenuate/scripts/batch-attenuate.sh
```

呼び出しが戻ったら、スクリプトが出した処理サマリを報告する。`exit=0` なら成功、非0なら失敗サマリをそのまま報告する。

## 入力・出力のルール（スクリプトと同じ）

| 項目 | 内容 |
|------|------|
| 入力ディレクトリ | `workspace/attenuate-input/`（デフォルト） |
| マニフェスト | **`attenuate-input/attenuate.txt` 必須**。行順で処理。未記載の `.mov` は無視 |
| 最低エントリ数 | **1以上**。0 はエラー |
| 出力ディレクトリ | `workspace/attenuate-output/`（デフォルト） |
| 出力ファイル名 | **ベース名 + `_attenuated.mov`** |
| 減衰方式 | `ambimux attenuate` — `--db` は `@` の値 |

### `attenuate.txt` の書式

```text
# コメントと空行は無視
clip_a.mov@3.5
clip_b.mov@6
clip_c.mov@0
```

- 1行 = 入力ディレクトリ直下の **ベース名のみ** + `@` + 下げ幅（dB）
- `@` の値は CLI の `--db` と同じ（0 または正の数）。`@0` はパススルー（コピー）
- ファイル名に空白・サブディレクトリは不可
- 同じファイルを複数行書いてはいけない（出力が衝突する）

## フォルダ構造

```
workspace/
├── attenuate-input/   # 減衰する .mov + 必須の attenuate.txt
└── attenuate-output/  # {base}_attenuated.mov
```

`workspace/` は `.gitignore` 想定。出力は常に `.mov`。

## エラーハンドリング

### `attenuate.txt` が無い / 有効行が 0

**原因:**
- `attenuate-input/attenuate.txt` が存在しない、またはコメントと空行以外が無い

**対処:**
- `basename.mov@DB` を1行以上書く

### 書式エラー（空白・サブディレクトリ・`@` 無し・負の dB・重複・ファイル未存在）

**原因:**
- 行に空白がある、パス区切りがある、`@DB` が無い、DB が 0 未満または数値でない、同じ `.mov` が複数行、記載したファイルが無い

**対処:**
- 入力ディレクトリ直下のベース名のみにする
- `@` のあとに 0 以上の数を書く（例: `clip.mov@3.5`）
- 1ファイルにつき1行

### `attenuateGainMustNotBoost`

**原因:**
- ゲインが正（ブースト）で渡された

**対処:**
- `attenuate.txt` の `@` 値は下げ幅（0 以上）にする。スクリプト側でも負数は拒否する

### `expectedAPACAudio`

**原因:**
- Ambisonics 主トラックが APAC ではなく LPCM

**対処:**
- 先に mux スキルで `--audio-output apac` したクリップを使う

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

### `invalidChannelCount`

**原因:**
- Ambisonics として解釈できないチャンネル数の APAC トラックがある

**対処:**
- 4・9・16ch Ambisonics + 任意の 1/2ch フォールバック構成に揃える

### `Cannot Encode` (エラーコード -11834)

**原因:**
- サンドボックス内で実行された

**対処:**
- `required_permissions: ["all"]` を指定してサンドボックスなしで実行する

## 例

入力ファイルの組み合わせの参考は [examples.md](examples.md)。実行は **batch-attenuate.sh** のみとする。
