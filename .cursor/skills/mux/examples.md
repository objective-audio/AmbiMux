# Examples: mux

## Example 1: 外部オーディオ（APAC）とペアリング

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

## Example 2: 外部オーディオ（LPCM WAV）とペアリング

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

## Example 3: 外部オーディオなし → 埋め込みオーディオにフォールバック

入力（`workspace/sources/`）:
- `scene_b.mov`（外部オーディオなし、埋め込み 4ch LPCM あり）

処理:
1. 外部オーディオ（`scene_b*.mp4` / `.wav` / `.aiff`）を探す → 見つからない
2. `ffprobe` で埋め込みオーディオのチャンネル数を確認 → 4ch → 変換対象
3. `--video` のみで変換

コマンド実行例:
```bash
.build/release/ambimux \
  --video "workspace/sources/scene_b.mov" \
  --output "workspace/export/scene_b_ambimux.mov"
```

出力（`workspace/export/`）:
- `scene_b_ambimux.mov`（埋め込みLPCMをAPACに変換、フォールバックトラックなし）

## Example 4: 複数 `.mov` を一括変換（外部・埋め込み・スキップ混在）

入力（`workspace/sources/`）:
- `2026_0211_scene_a.mov` → `2026_0211_scene_a_apac00000000.mp4`（外部 APAC あり）
- `2026_0212_demo.mov` → `2026_0212_demo_audio.wav`（外部 LPCM WAV あり）
- `2026_0213_field.mov` → 外部オーディオなし、埋め込み 4ch LPCM あり
- `test.mov` → 外部オーディオなし、埋め込みオーディオなし

処理:
1. `2026_0211_scene_a.mov` + `2026_0211_scene_a_apac00000000.mp4` → `workspace/export/2026_0211_scene_a_ambimux.mov`（APACパススルー）
2. `2026_0212_demo.mov` + `2026_0212_demo_audio.wav` → `workspace/export/2026_0212_demo_ambimux.mov`（LPCMをAPACに変換）
3. `2026_0213_field.mov` → 外部オーディオなし → 埋め込み4chを確認 → `workspace/export/2026_0213_field_ambimux.mov`（埋め込みLPCMをAPACに変換）
4. `test.mov` → 外部オーディオなし → 埋め込みオーディオなし → スキップ

最終サマリ:
- 成功: 3件
- スキップ: 1件（`test.mov`）

## Example 5: .mp4 と .wav が両方ある場合（.mp4 優先）

入力（`workspace/sources/`）:
- `clip.mov`
- `clip_apac.mp4`（APAC）
- `clip.wav`（4ch LPCM）

処理:
- `clip.mov` + `clip_apac.mp4` → `workspace/export/clip_ambimux.mov`
  - `.mp4` が優先されるため、`clip.wav` は使用されない

## Example 6: .wav と .aiff が両方ある場合（.wav 優先）

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
- 外部オーディオの LPCM ファイルは 4チャンネル B-format Ambisonics である必要があります
- 埋め込みオーディオは 4・9・16 チャンネルの LPCM である必要があります
