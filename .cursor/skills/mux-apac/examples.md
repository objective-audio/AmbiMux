# Examples: mux-apac

## Example 1: work/ の2ファイルを指定して多重化

入力:
- Video: `work/sources/video.mov`
- Audio(APAC): `work/sources/audio_apac.mp4`

出力:
- `work/export/video_ambimux.mov`

コマンド:

```bash
.build/release/ambimux \
  --apac work/sources/audio_apac.mp4 \
  --video work/sources/video.mov \
  --output work/export/video_ambimux.mov
```

## Example 2: 複数候補がある場合（選択→出力名を決める）

1. `work/sources/` を一覧し、`*.mov` を video候補、`*.mp4` を audio候補として列挙する。
2. ユーザーに video/audio をそれぞれ1つずつ選ばせる。
3. 出力は `work/export/<videoBaseName>_ambimux.mov` をデフォルトにする（上書き防止で `--output` を明示）。
