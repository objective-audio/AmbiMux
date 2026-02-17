# Examples: mux-lpcm

## Example 1: 単一WAVファイルとのペアリング

入力（`work/sources/`）:
- `video.mov`
- `video.wav`（4ch, 48kHz, 32-bit float LPCM）

出力（`work/export/`）:
- `video_ambimux.mov`（APAC圧縮済み空間音声 + ステレオフォールバック）

コマンド実行例:
```bash
.build/release/ambimux \
  --lpcm "work/sources/video.wav" \
  --video "work/sources/video.mov" \
  --output "work/export/video_ambimux.mov"
```

## Example 2: 複数 `.mov` を一括変換（WAV/AIFF混在）

入力（`work/sources/`）:
- `2026_0211_nicopri.mov` → `2026_0211_nicopri.wav`（前方一致）
- `2026_0212_demo.mov` → `2026_0212_demo_audio.aiff`（前方一致）
- `test.mov` → （該当なし）

処理:
1. `2026_0211_nicopri.mov` + `2026_0211_nicopri.wav` → `work/export/2026_0211_nicopri_ambimux.mov`
2. `2026_0212_demo.mov` + `2026_0212_demo_audio.aiff` → `work/export/2026_0212_demo_ambimux.mov`
3. `test.mov` → スキップ（警告: ペアが無い）

最終サマリ:
- 成功: 2件
- スキップ: 1件（`test.mov`）

## Example 3: 優先順位（.wav > .aiff）

入力（`work/sources/`）:
- `clip.mov`
- `clip.wav`（4ch LPCM）
- `clip.aiff`（4ch LPCM）

処理:
- `clip.mov` + `clip.wav` → `work/export/clip_ambimux.mov`
  - `.wav` が優先されるため、`clip.aiff` は使用されない

## Example 4: 前方一致の例

入力（`work/sources/`）:
- `Timeline 2.mov`
- `Timeline 2-injected.wav`（前方一致）

処理:
- `Timeline 2.mov` + `Timeline 2-injected.wav` → `work/export/Timeline 2_ambimux.mov`
  - ベース名 `Timeline 2` で始まる `.wav` ファイルが見つかる

## Example 5: 大容量ファイルの変換

入力（`work/sources/`）:
- `4k_video.mov`（4096x4096, 2.7GB, HEVC）
- `4k_video.wav`（4ch, 48kHz, 216秒）

出力（`work/export/`）:
- `4k_video_ambimux.mov`（2.6GB）
  - Audio track 1: 4チャンネル APAC (Ambisonics)
  - Audio track 2: 2チャンネル ステレオフォールバック（元動画から）

処理時間: 約7秒（Apple Silicon Mac）

## 注意事項

- 全てのコマンドは `required_permissions: ["all"]` を指定してサンドボックスなしで実行する必要があります
- APACエンコーダーはサンドボックス内では動作しません（AVErrorCannotEncode -11834が発生）
- 入力オーディオファイルは4チャンネル B-format Ambisonics である必要があります
