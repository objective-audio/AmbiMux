---
name: sbs
description: Converts tagless VR180 videos (Half-Equirectangular SBS) to MV-HEVC with avconvert for Vision Pro playback. Runs batch conversion automatically when invoked. Use when avconvert, APMP, MV-HEVC, or VR180 conversion is mentioned.
---

# VR180 から MV-HEVC への変換

メタデータが埋め込まれていないVR180動画を、macOSの`avconvert`を使ってApple Vision Pro再生用のMV-HEVC形式に変換する。

## スキル呼び出し時の動作

スキルが呼ばれたら、**確認なしでバッチ変換を実行する**。完了まで待機する。

**実行コマンド（リポジトリルートで）:**

```bash
bash .cursor/skills/sbs/scripts/convert-vr180.sh workspace/sbs-input workspace/mux-input
```

**Shell 実行時の必須オプション:**

- `required_permissions: ["all"]` — avconvert はサンドボックス内で失敗するため必須
- `block_until_ms: 1209600000` — 14日間（長時間ジョブ用。通常の VR180 バッチでは上限に達しない想定）
- `is_background: false` — 完了まで待機

**パス（固定）:**

- 入力: `workspace/sbs-input`
- 出力: `workspace/mux-input`

## 前提条件

- avconvert が使える macOS（標準搭載）
- MV-HEVC判定用の ffprobe（FFmpeg）
- ソース: VR180 Half-Equirectangular Side-by-Side（SBS）、通常 8192x4096 または同様の 2:1 アスペクト比

## 補足

- **APMP と MV-HEVC**: APMP（PresetPassthrough）は魚眼VR180用。Equirectangular SBS VR180 には PresetMVHEVC を使用する。
- **処理時間**: 解像度・尺・マシンにより大きく変わる。目安として約20分のソースで約80分程度かかる例がある。
- **出力**: HEVC（MV-HEVC）映像とAAC音声を含む .mov
