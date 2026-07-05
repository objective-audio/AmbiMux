#!/usr/bin/env bash
# Batch join: concatenate all .mov files under input dir in filename order into one output.
# Invokes repository .build/release/ambimux join (passthrough). Run from repo root or anywhere.
#
# Usage: batch-join.sh [input_dir] [output_dir] [repo_root]
# Defaults: workspace/join-input  workspace/join-output  (repo root = 4 levels up from this script)
#
# Environment:
#   BATCH_JOIN_SKIP_BUILD=1  — skip "swift build -c release" (not recommended; matches SKILL when unset)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

INPUT_DIR="${1:-workspace/join-input}"
OUTPUT_DIR="${2:-workspace/join-output}"
REPO_ROOT="${3:-$DEFAULT_REPO}"

if [[ ! -d "$REPO_ROOT" ]]; then
  echo "error: repo root is not a directory: $REPO_ROOT" >&2
  exit 1
fi
cd "$REPO_ROOT" || exit 1

AMBIMUX="$REPO_ROOT/.build/release/ambimux"

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

if [[ -z "${BATCH_JOIN_SKIP_BUILD:-}" ]]; then
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

if ((MOV_COUNT == 0)); then
  echo "error: no .mov files found in $INPUT_DIR" >&2
  exit 1
fi

if ((MOV_COUNT == 1)); then
  echo "error: at least two .mov files are required (found 1: ${MOV_LIST[0]})" >&2
  exit 1
fi

first_base="$(basename "${MOV_LIST[0]}" .mov)"
out_raw="$OUTPUT_DIR/${first_base}_joined.mov"
out_abs="$(abs_path "$out_raw")"

MOV_ABS=()
for mov in "${MOV_LIST[@]}"; do
  MOV_ABS+=("$(abs_path "$mov")")
done

echo ""
echo "==> Joining ${MOV_COUNT} clips (filename order)"
for mov in "${MOV_LIST[@]}"; do
  echo "  - $(basename "$mov")"
done
echo "==> Output: $out_abs"
echo ""

if "$AMBIMUX" join "${MOV_ABS[@]}" --output "$out_abs"; then
  echo ""
  echo "## 処理結果サマリ"
  echo ""
  echo "### 入力"
  echo "- \`.mov\`ファイル: ${MOV_COUNT}件（ファイル名順）"
  for mov in "${MOV_LIST[@]}"; do
    echo "  - $(basename "$mov")"
  done
  echo ""
  echo "### 結果"
  echo "- 成功: 1件"
  echo "- 出力: $out_abs"
  exit 0
else
  ec=$?
  echo ""
  echo "## 処理結果サマリ"
  echo ""
  echo "### 入力"
  echo "- \`.mov\`ファイル: ${MOV_COUNT}件（ファイル名順）"
  echo ""
  echo "### 結果"
  echo "- 失敗: ambimux join exit $ec"
  echo "- 出力は作成されなかった可能性があります: $out_abs"
  exit "$ec"
fi
