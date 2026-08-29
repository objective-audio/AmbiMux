# Examples: attenuate

## Example 1: ファイルごとに異なる減衰量（attenuate.txt）

入力（`workspace/attenuate-input/`）:

- `clip_a_ambimux.mov`
- `clip_b_ambimux.mov`
- `clip_c_ambimux.mov`（リストに無いので処理されない）
- `attenuate.txt`:

```text
# @ の値は --db と同じ下げ幅（dB）
clip_a_ambimux.mov@3.5
clip_b_ambimux.mov@6
```

出力（`workspace/attenuate-output/`）:

- `clip_a_ambimux_attenuated.mov`（3.5 dB 下げ）
- `clip_b_ambimux_attenuated.mov`（6 dB 下げ）

実行:

```bash
.cursor/skills/attenuate/scripts/batch-attenuate.sh
```

## Example 2: 0 dB（パススルー）

入力（`workspace/attenuate-input/`）:

- `clip_a.mov`
- `attenuate.txt`:

```text
clip_a.mov@0
```

出力:

- `clip_a_attenuated.mov`（レベル変更なし、コピー）

実行は Example 1 と同じ `batch-attenuate.sh`。

## Example 3: 手動 CLI

入力（`workspace/attenuate-input/`）:

- `clip_a.mov`

コマンド実行例:

```bash
.build/release/ambimux attenuate \
  workspace/attenuate-input/clip_a.mov \
  --db 3.5 \
  --output workspace/attenuate-output/clip_a_attenuated.mov
```

## Example 4: マニフェスト不正（失敗）

| 状況 | 結果 |
|------|------|
| `attenuate.txt` が無い | スクリプトがエラー終了 |
| `attenuate.txt` の有効行が 0 行 | スクリプトがエラー終了 |
| `clip.mov`（`@DB` 無し） | スクリプトがエラー終了 |
| `clip.mov@-3`（負の dB） | スクリプトがエラー終了 |
| 同じファイルが複数行 | スクリプトがエラー終了 |
| `attenuate.txt` に書いたファイルが無い | スクリプトがエラー終了 |

パースエラーのときは `ambimux attenuate` は呼ばれない。

## Example 5: APAC ではない入力（失敗）

入力（`workspace/attenuate-input/`）:

- `clip_lpcm.mov`（LPCM Ambisonics）
- `attenuate.txt`: `clip_lpcm.mov@3`

結果:

- `expectedAPACAudio` でそのファイルは失敗
- 他の行があれば処理は続く

**対処:** mux スキルで APAC 出力してから減衰する。

## 典型的なワークフロー

1. **mux** — `workspace/mux-input/` → `workspace/mux-output/*_ambimux.mov`
2. 必要なら **join** — `workspace/join-output/{先頭}_joined.mov`
3. 減衰したい APAC MOV を `workspace/attenuate-input/` にコピー
4. `attenuate-input/attenuate.txt` に `file.mov@DB` を書く
5. **attenuate** — `batch-attenuate.sh` → `workspace/attenuate-output/{base}_attenuated.mov`

## 注意事項

- `attenuate.txt` が無いときは実行できない。減衰量はファイルごとにマニフェストで決まる
- 未記載の `.mov` は無視される
- `@` の単位は dB（CLI `--db` と同じ）。0 以上のみ
- 入力は APAC Ambisonics が必要（mux 済みクリップを想定）
- APAC 再エンコードのため、サンドボックスなし（`required_permissions: ["all"]`）で実行する
