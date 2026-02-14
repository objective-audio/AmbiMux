# Examples: mux-apac

## Example 1: 単一ペアの一括変換

入力（`work/sources/`）:
- `video.mov`
- `video_apac.mp4`

出力（`work/export/`）:
- `video_ambimux.mov`

## Example 2: 複数 `.mov` を一括変換

入力（`work/sources/`）:
- `2026_0211_nicopri.mov` → `2026_0211_nicopri_apac00000000.mp4`（前方一致）
- `2026_0212_demo.mov` → `2026_0212_demo_audio.mp4`（前方一致）
- `test.mov` → （該当なし）

処理:
1. `2026_0211_nicopri.mov` + `2026_0211_nicopri_apac00000000.mp4` → `work/export/2026_0211_nicopri_ambimux.mov`
2. `2026_0212_demo.mov` + `2026_0212_demo_audio.mp4` → `work/export/2026_0212_demo_ambimux.mov`
3. `test.mov` → スキップ（警告: ペアが無い）

最終サマリ:
- 成功: 2件
- スキップ: 1件（`test.mov`）
