# Examples: join

## Example 1: mux 出力の連結（全尺・ファイル名順）

入力（`workspace/join-input/`）:

- `2026_0211_scene_a_ambimux.mov`
- `2026_0212_demo_ambimux.mov`
- `2026_0213_field_ambimux.mov`

（`join.txt` なし）

出力（`workspace/join-output/`）:

- `2026_0211_scene_a_ambimux_joined.mov`（先頭ファイル名 + `_joined.mov`）

実行:

```bash
.cursor/skills/join/scripts/batch-join.sh
```

結合順: ファイル名順（上記3本の並び）。

## Example 1b: バッチで区間指定（join.txt）

入力（`workspace/join-input/`）:

- `clip_a.mov`
- `clip_b.mov`
- `clip_c.mov`（リストに無いので結合されない）
- `join.txt`:

```text
# 行順 = 結合順。@START-END は秒
clip_b.mov@0-8.0
clip_a.mov@1.5-12.0
clip_a.mov@20-25
```

出力:

- `clip_b_joined.mov`（先頭行のベース名）

実行は Example 1 と同じ `batch-join.sh`。

## Example 1c: 1セグメントの切り出し（join.txt）

入力（`workspace/join-input/`）:

- `clip_a.mov`
- `join.txt`:

```text
clip_a.mov@1.5-12.0
```

出力:

- `clip_a_joined.mov`（指定区間のみ、パススルー）

実行は Example 1 と同じ `batch-join.sh`。

## Example 2: 手動 CLI

入力（`workspace/join-input/`）:

- `clip_a.mov`
- `clip_b.mov`

コマンド実行例:

```bash
.build/release/ambimux join \
  workspace/join-input/clip_a.mov \
  workspace/join-input/clip_b.mov \
  --output workspace/join-output/clip_a_joined.mov
```

## Example 2b: 区間指定（秒・CLI）

各クリップの `[start, end)` を `@START-END` で指定（混在可。`@` 無しは全尺）:

```bash
.build/release/ambimux join \
  workspace/join-input/clip_a.mov@1.5-12.0 \
  workspace/join-input/clip_b.mov@0-8.0 \
  --output workspace/join-output/clip_a_joined.mov
```

## Example 3: フォーマット不一致（失敗）

入力（`workspace/join-input/`）:

- `clip_apac.mov`（`--audio-output apac` で mux 済み）
- `clip_lpcm.mov`（`--audio-output lpcm` で mux 済み）

結果:

- `concatFormatMismatch` で失敗
- 出力ファイルは作成されない

**対処:** すべて同じ音声出力形式（通常は APAC）で mux してから結合する。

## Example 4: 入力不足（失敗）

| 状況 | 結果 |
|------|------|
| `join-input/` に `.mov` が0件（かつ `join.txt` なし） | スクリプトがエラー終了 |
| `join-input/` に `.mov` が1件のみ（かつ `join.txt` なし） | その1本を全尺で書き出す |
| `join.txt` の有効行が0行 | スクリプトがエラー終了 |
| `join.txt` の有効行が1行（`@START-END` あり） | 切り出しとして成功 |
| `join.txt` に書いたファイルが無い | スクリプトがエラー終了 |

## 典型的なワークフロー

1. **mux** — `workspace/mux-input/` → `workspace/mux-output/*_ambimux.mov`
2. 結合したい `*_ambimux.mov` を `workspace/join-input/` にコピー
3. 区間・順序を指定するなら `join-input/join.txt` を書く
4. **join** — `batch-join.sh` → `workspace/join-output/{先頭}_joined.mov`

## 注意事項

- `join.txt` が無いとき、結合順は **ファイル名** で決まる。意図した順序にするため、ファイル名のプレフィックス（日付・シーン番号等）を揃える
- `join.txt` があるとき、結合順・区間は **行の内容** で決まる（未記載の `.mov` は無視）
- 全クリップの映像解像度・フレームレート・音声フォーマットが一致している必要がある
- 結合はパススルーのため、APAC エンコードは行われない（mux 済みクリップをそのまま連結）
- 区間の単位は秒（`path@START-END`）。CLI と `join.txt` で同じ書式
