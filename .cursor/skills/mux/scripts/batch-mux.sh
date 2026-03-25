#!/usr/bin/env bash
# Batch mux: pair external audio (.mp4/.wav/.aiff) with each .mov under input dir, else use embedded Ambisonics (4/9/16ch).
# Invokes repository .build/release/ambimux (APAC output). Run from repo root or anywhere.
#
# Usage: batch-mux.sh [input_dir] [output_dir] [repo_root]
# Defaults: workspace/mux-input  workspace/output  (repo root = 4 levels up from this script)
#
# Environment:
#   BATCH_MUX_SKIP_BUILD=1  — skip "swift build -c release" (not recommended; matches SKILL when unset)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

INPUT_DIR="${1:-workspace/mux-input}"
OUTPUT_DIR="${2:-workspace/output}"
REPO_ROOT="${3:-$DEFAULT_REPO}"

if [[ ! -d "$REPO_ROOT" ]]; then
  echo "error: repo root is not a directory: $REPO_ROOT" >&2
  exit 1
fi
cd "$REPO_ROOT" || exit 1

AMBIMUX="$REPO_ROOT/.build/release/ambimux"

pick_external_audio() {
  local dir="$1" base="$2" ext found
  for ext in mp4 wav aiff; do
    found="$(find "$dir" -maxdepth 1 -type f -iname "${base}*.${ext}" 2>/dev/null | LC_ALL=C sort -u | head -n 1)"
    if [[ -n "$found" ]]; then
      printf '%s\n' "$found"
      return 0
    fi
  done
  return 1
}

embedded_ambisonics_ok() {
  local mov="$1"
  ffprobe -v quiet -show_streams -select_streams a "$mov" 2>&1 | grep -E '^channels=(4|9|16)$' -q
}

abs_path() {
  # $1: path (file or dir)
  local d
  d="$(cd "$(dirname "$1")" && pwd)"
  printf '%s/%s\n' "$d" "$(basename "$1")"
}

mkdir -p "$OUTPUT_DIR"

if [[ ! -d "$INPUT_DIR" ]]; then
  echo "error: input directory does not exist: $INPUT_DIR" >&2
  exit 1
fi

if [[ -z "${BATCH_MUX_SKIP_BUILD:-}" ]]; then
  echo "==> swift build -c release (repo: $REPO_ROOT)"
  (cd "$REPO_ROOT" && swift build -c release) || {
    echo "error: swift build failed" >&2
    exit 1
  }
fi

if [[ ! -x "$AMBIMUX" ]]; then
  echo "error: ambimux not found or not executable: $AMBIMUX" >&2
  exit 1
fi

MOV_LIST=()
while IFS= read -r mov; do
  [[ -n "$mov" ]] && MOV_LIST+=("$mov")
done < <(find "$INPUT_DIR" -name "*.mov" -type f | LC_ALL=C sort)
MOV_COUNT="${#MOV_LIST[@]}"

success=0
skip=0
fail=0
declare -a SKIP_ENTRIES FAIL_ENTRIES

for mov in "${MOV_LIST[@]}"; do
  [[ -f "$mov" ]] || continue
  base="$(basename "$mov" .mov)"
  mov_abs="$(abs_path "$mov")"
  out_raw="$OUTPUT_DIR/${base}_ambimux.mov"
  out_abs="$(abs_path "$out_raw")"

  echo ""
  echo "---- $base ----"

  audio_path=""
  if audio_path="$(pick_external_audio "$INPUT_DIR" "$base")"; then
    echo "external audio: $audio_path"
    audio_abs="$(abs_path "$audio_path")"
    if "$AMBIMUX" --audio "$audio_abs" --video "$mov_abs" --output "$out_abs" --audio-output apac; then
      ((success += 1)) || true
    else
      ec=$?
      ((fail += 1)) || true
      FAIL_ENTRIES+=("$base.mov (エラー: ambimux exit $ec)")
    fi
    continue
  fi

  if embedded_ambisonics_ok "$mov"; then
    echo "embedded Ambisonics (4/9/16ch) — mux without --audio"
    if "$AMBIMUX" --video "$mov_abs" --output "$out_abs" --audio-output apac; then
      ((success += 1)) || true
    else
      ec=$?
      ((fail += 1)) || true
      FAIL_ENTRIES+=("$base.mov (エラー: ambimux exit $ec)")
    fi
  else
    echo "skip: no prefix-matched .mp4/.wav/.aiff and no embedded 4/9/16ch audio" >&2
    ((skip += 1)) || true
    SKIP_ENTRIES+=("$base.mov (理由: 外部オーディオなし・埋め込みオーディオも対象外)")
  fi
done

echo ""
echo "## 処理結果サマリ"
echo ""
echo "### 検出されたファイル"
echo "- \`.mov\`ファイル: ${MOV_COUNT}件"
echo ""
echo "### 変換結果"
echo "- 成功した変換: ${success}件"
echo "- スキップした\`.mov\`: ${skip}件"
echo "- 失敗した変換: ${fail}件"
echo ""
echo "### 統計"
echo "- 成功: ${success}件"
echo "- スキップ: ${skip}件"
echo "- 失敗: ${fail}件"

if ((skip > 0)); then
  echo ""
  echo "スキップした\`.mov\`:"
  for e in "${SKIP_ENTRIES[@]}"; do
    echo "- $e"
  done
fi

if ((fail > 0)); then
  echo ""
  echo "失敗した変換:"
  for e in "${FAIL_ENTRIES[@]}"; do
    echo "- $e"
  done
fi
