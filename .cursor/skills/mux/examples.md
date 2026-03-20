# Examples: mux

## Example 1: 外部オーディオ（APAC）とペアリング

入力（`workspace/mux-input/`）:
- `video.mov`
- `video_apac00000000.mp4`（APAC圧縮済み）

出力（`workspace/output/`）:
- `video_ambimux.mov`

コマンド実行例:
```bash
.build/release/ambimux \
  --audio "workspace/mux-input/video_apac00000000.mp4" \
  --video "workspace/mux-input/video.mov" \
  --output "workspace/output/video_ambimux.mov"
```

## Example 2: 外部オーディオ（LPCM WAV）とペアリング

入力（`workspace/mux-input/`）:
- `video.mov`
- `video.wav`（4ch, 48kHz, 32-bit float LPCM）

出力（`workspace/output/`）:
- `video_ambimux.mov`（LPCMからAPACに変換された空間音声 + ステレオフォールバック）

コマンド実行例:
```bash
.build/release/ambimux \
  --audio "workspace/mux-input/video.wav" \
  --video "workspace/mux-input/video.mov" \
  --output "workspace/output/video_ambimux.mov"
```

## Example 3: 外部オーディオなし → 埋め込み Ambisonics（＋任意でモノ/ステレオ）

入力（`workspace/mux-input/`）:
- `scene_b.mov`（外部オーディオなし、埋め込み 4ch LPCM あり）
- または、同じく外部オーディオなしで **4ch Ambisonics + 2ch ステレオ** の2本が埋め込まれている `.mov`

処理:
1. 外部オーディオ（`scene_b*.mp4` / `.wav` / `.aiff`）を探す → 見つからない
2. `ffprobe` で埋め込みを確認 → **4/9/16ch の Ambisonics が少なくとも1本**あれば変換対象
3. `--video` のみで変換

コマンド実行例:
```bash
.build/release/ambimux \
  --video "workspace/mux-input/scene_b.mov" \
  --output "workspace/output/scene_b_ambimux.mov"
```

出力（`workspace/output/`）:
- `scene_b_ambimux.mov`（主トラック: 埋め込み Ambisonics を APAC に変換）
- 入力に **1/2ch の別トラック** があれば、**第2音声トラックとしてパススルー**（フォールバック）され、検証ログ上は `Audio tracks: 2` になることがある

## Example 4: 複数 `.mov` を一括変換（外部・埋め込み・スキップ混在）

入力（`workspace/mux-input/`）:
- `2026_0211_scene_a.mov` → `2026_0211_scene_a_apac00000000.mp4`（外部 APAC あり）
- `2026_0212_demo.mov` → `2026_0212_demo_audio.wav`（外部 LPCM WAV あり）
- `2026_0213_field.mov` → 外部オーディオなし、埋め込み 4ch LPCM あり
- `test.mov` → 外部オーディオなし、埋め込みオーディオなし

処理:
1. `2026_0211_scene_a.mov` + `2026_0211_scene_a_apac00000000.mp4` → `workspace/output/2026_0211_scene_a_ambimux.mov`（APACパススルー）
2. `2026_0212_demo.mov` + `2026_0212_demo_audio.wav` → `workspace/output/2026_0212_demo_ambimux.mov`（LPCMをAPACに変換）
3. `2026_0213_field.mov` → 外部オーディオなし → 埋め込み Ambisonics を確認 → `workspace/output/2026_0213_field_ambimux.mov`（主: 埋め込みを APAC に。ステレオ等が別トラックにあれば第2トラックも出力）
4. `test.mov` → 外部オーディオなし → 埋め込みオーディオなし → スキップ

最終サマリ:
- 成功: 3件
- スキップ: 1件（`test.mov`）

## Example 5: .mp4 と .wav が両方ある場合（.mp4 優先）

入力（`workspace/mux-input/`）:
- `clip.mov`
- `clip_apac.mp4`（APAC）
- `clip.wav`（4ch LPCM）

処理:
- `clip.mov` + `clip_apac.mp4` → `workspace/output/clip_ambimux.mov`
  - `.mp4` が優先されるため、`clip.wav` は使用されない

## Example 6: .wav と .aiff が両方ある場合（.wav 優先）

入力（`workspace/mux-input/`）:
- `clip.mov`
- `clip.wav`（4ch LPCM）
- `clip.aiff`（4ch LPCM）

処理:
- `clip.mov` + `clip.wav` → `workspace/output/clip_ambimux.mov`
  - `.wav` が優先されるため、`clip.aiff` は使用されない

## 注意事項

- 全てのコマンドは `required_permissions: ["all"]` を指定してサンドボックスなしで実行する必要があります
- APACエンコーダーはサンドボックス内では動作しません（AVErrorCannotEncode -11834 が発生）
- 外部オーディオの LPCM ファイルは 4チャンネル B-format Ambisonics である必要があります
- 埋め込みの **主トラック（Ambisonics）** は 4・9・16 チャンネルである必要がある（モノ/ステレオの別トラックは任意で第2トラックに含まれる）
