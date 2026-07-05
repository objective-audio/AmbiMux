# Examples: join

## Example 1: mux 出力の連結

入力（`workspace/join-input/`）:

- `2026_0211_scene_a_ambimux.mov`
- `2026_0212_demo_ambimux.mov`
- `2026_0213_field_ambimux.mov`

出力（`workspace/join-output/`）:

- `2026_0211_scene_a_ambimux_joined.mov`（先頭ファイル名 + `_joined.mov`）

実行:

```bash
.cursor/skills/join/scripts/batch-join.sh
```

結合順: ファイル名順（上記3本の並び）。

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
| `join-input/` に `.mov` が0件 | スクリプトがエラー終了 |
| `join-input/` に `.mov` が1件のみ | スクリプトがエラー終了（2本以上必要） |

## 典型的なワークフロー

1. **mux** — `workspace/mux-input/` → `workspace/mux-output/*_ambimux.mov`
2. 結合したい `*_ambimux.mov` を `workspace/join-input/` にコピー
3. **join** — `batch-join.sh` → `workspace/join-output/{先頭}_joined.mov`

## 注意事項

- 結合順は **ファイル名** で決まる。意図した順序にするため、ファイル名のプレフィックス（日付・シーン番号等）を揃える
- 全クリップの映像解像度・フレームレート・音声フォーマットが一致している必要がある
- 結合はパススルーのため、APAC エンコードは行われない（mux 済みクリップをそのまま連結）
