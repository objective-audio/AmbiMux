# Examples: mux-audio

## Example 1: APAC ファイルとのペアリング

入力（`workspace/sources/`）:
- `video.mov`
- `video_apac00000000.mp4`（APAC圧縮済み）

出力（`workspace/export/`）:
- `video_ambimux.mov`

コマンド実行例:
```bash
.build/release/ambimux \
  --audio "workspace/sources/video_apac00000000.mp4" \
  --video "workspace/sources/video.mov" \
  --output "workspace/export/video_ambimux.mov"
```

## Example 2: LPCM WAV ファイルとのペアリング

入力（`workspace/sources/`）:
- `video.mov`
- `video.wav`（4ch, 48kHz, 32-bit float LPCM）

出力（`workspace/export/`）:
- `video_ambimux.mov`（LPCMからAPACに変換された空間音声 + ステレオフォールバック）

コマンド実行例:
```bash
.build/release/ambimux \
  --audio "workspace/sources/video.wav" \
  --video "workspace/sources/video.mov" \
  --output "workspace/export/video_ambimux.mov"
```

## Example 3: 複数 `.mov` を一括変換（APAC と LPCM 混在）

入力（`workspace/sources/`）:
- `2026_0211_scene_a.mov` → `2026_0211_scene_a_apac00000000.mp4`（前方一致、APAC）
- `2026_0212_demo.mov` → `2026_0212_demo_audio.wav`（前方一致、LPCM）
- `test.mov` → （該当なし）

処理:
1. `2026_0211_scene_a.mov` + `2026_0211_scene_a_apac00000000.mp4` → `workspace/export/2026_0211_scene_a_ambimux.mov`（APACパススルー）
2. `2026_0212_demo.mov` + `2026_0212_demo_audio.wav` → `workspace/export/2026_0212_demo_ambimux.mov`（LPCMをAPACに変換）
3. `test.mov` → スキップ（警告: ペアが無い）

最終サマリ:
- 成功: 2件
- スキップ: 1件（`test.mov`）

## Example 4: .mp4 と .wav が両方ある場合（.mp4 優先）

入力（`workspace/sources/`）:
- `clip.mov`
- `clip_apac.mp4`（APAC）
- `clip.wav`（4ch LPCM）

処理:
- `clip.mov` + `clip_apac.mp4` → `workspace/export/clip_ambimux.mov`
  - `.mp4` が優先されるため、`clip.wav` は使用されない

## Example 5: .wav と .aiff が両方ある場合（.wav 優先）

入力（`workspace/sources/`）:
- `clip.mov`
- `clip.wav`（4ch LPCM）
- `clip.aiff`（4ch LPCM）

処理:
- `clip.mov` + `clip.wav` → `workspace/export/clip_ambimux.mov`
  - `.wav` が優先されるため、`clip.aiff` は使用されない

## 注意事項

- 全てのコマンドは `required_permissions: ["all"]` を指定してサンドボックスなしで実行する必要があります
- APACエンコーダーはサンドボックス内では動作しません（AVErrorCannotEncode -11834 が発生）
- 入力 LPCM ファイルは 4チャンネル B-format Ambisonics である必要があります
