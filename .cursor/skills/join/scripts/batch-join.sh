#!/usr/bin/env bash
# Batch join: concatenate MOV clips into one output via ambimux join (passthrough).
# Invokes repository .build/release/ambimux join. Run from repo root or anywhere.
#
# Usage: batch-join.sh [input_dir] [output_dir] [repo_root]
# Defaults: workspace/join-input  workspace/join-output  (repo root = 4 levels up from this script)
#
# If input_dir/join.txt exists, use it as a manifest (line order + optional path@START-END).
# Otherwise join all .mov files under input_dir in filename order (full length).
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

# Strip optional @START-END suffix; print the path portion only.
path_without_range() {
  local spec="$1"
  if [[ "$spec" == *@* ]]; then
    local suffix="${spec##*@}"
    if [[ "$suffix" =~ ^[0-9]+([.][0-9]+)?-[0-9]+([.][0-9]+)?$ ]]; then
      printf '%s\n' "${spec%@*}"
      return
    fi
  fi
  printf '%s\n' "$spec"
}

mkdir -p "$OUTPUT_DIR"

if [[ ! -d "$INPUT_DIR" ]]; then
  echo "error: input directory does not exist: $INPUT_DIR" >&2
  exit 1
fi

INPUT_DIR_ABS="$(cd "$INPUT_DIR" && pwd)"
JOIN_TXT="$INPUT_DIR_ABS/join.txt"

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

# JOIN_SPECS: arguments passed to ambimux join (abs path, optionally with @START-END)
# DISPLAY_SPECS: human-readable lines for logs
JOIN_SPECS=()
DISPLAY_SPECS=()
MODE=""

if [[ -f "$JOIN_TXT" ]]; then
  MODE="manifest"
  line_no=0
  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    line_no=$((line_no + 1))
    # Trim leading/trailing whitespace
    line="${raw_line#"${raw_line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue

    if [[ "$line" == *" "* || "$line" == *$'\t'* ]]; then
      echo "error: join.txt line $line_no has whitespace (filenames with spaces are not supported): $line" >&2
      exit 1
    fi

    if [[ "$line" == */* ]]; then
      echo "error: join.txt line $line_no must be a basename under the input dir (no subdirectories): $line" >&2
      exit 1
    fi

    file_part="$(path_without_range "$line")"
    if [[ "$file_part" != *.mov ]]; then
      echo "error: join.txt line $line_no must refer to a .mov file: $line" >&2
      exit 1
    fi

    mov_path="$INPUT_DIR_ABS/$file_part"
    if [[ ! -f "$mov_path" ]]; then
      echo "error: join.txt line $line_no: file not found: $mov_path" >&2
      exit 1
    fi

    mov_abs="$(abs_path "$mov_path")"
    if [[ "$file_part" == "$line" ]]; then
      JOIN_SPECS+=("$mov_abs")
      DISPLAY_SPECS+=("$file_part")
    else
      range_suffix="${line#"$file_part"}"
      JOIN_SPECS+=("${mov_abs}${range_suffix}")
      DISPLAY_SPECS+=("$line")
    fi
  done <"$JOIN_TXT"
else
  MODE="scan"
  while IFS= read -r mov; do
    [[ -n "$mov" ]] || continue
    mov_abs="$(abs_path "$mov")"
    JOIN_SPECS+=("$mov_abs")
    DISPLAY_SPECS+=("$(basename "$mov")")
  done < <(find "$INPUT_DIR_ABS" -maxdepth 1 -name "*.mov" -type f | LC_ALL=C sort)
fi

SEG_COUNT="${#JOIN_SPECS[@]}"

if ((SEG_COUNT == 0)); then
  if [[ "$MODE" == "manifest" ]]; then
    echo "error: join.txt has no segment entries: $JOIN_TXT" >&2
  else
    echo "error: no .mov files found in $INPUT_DIR" >&2
  fi
  exit 1
fi

first_file="$(path_without_range "${DISPLAY_SPECS[0]}")"
first_base="$(basename "$first_file" .mov)"
out_raw="$OUTPUT_DIR/${first_base}_joined.mov"
out_abs="$(abs_path "$out_raw")"

echo ""
if [[ "$MODE" == "manifest" ]]; then
  echo "==> Joining ${SEG_COUNT} segments (join.txt order)"
  echo "    manifest: $JOIN_TXT"
else
  echo "==> Joining ${SEG_COUNT} clips (filename order, full length)"
fi
for spec in "${DISPLAY_SPECS[@]}"; do
  echo "  - $spec"
done
echo "==> Output: $out_abs"
echo ""

if "$AMBIMUX" join "${JOIN_SPECS[@]}" --output "$out_abs"; then
  echo ""
  echo "## 処理結果サマリ"
  echo ""
  echo "### 入力"
  if [[ "$MODE" == "manifest" ]]; then
    echo "- モード: join.txt マニフェスト"
    echo "- セグメント: ${SEG_COUNT}件（行順）"
  else
    echo "- モード: ディレクトリ走査"
    echo "- \`.mov\`ファイル: ${SEG_COUNT}件（ファイル名順・全尺）"
  fi
  for spec in "${DISPLAY_SPECS[@]}"; do
    echo "  - $spec"
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
  if [[ "$MODE" == "manifest" ]]; then
    echo "- モード: join.txt マニフェスト"
    echo "- セグメント: ${SEG_COUNT}件"
  else
    echo "- モード: ディレクトリ走査"
    echo "- \`.mov\`ファイル: ${SEG_COUNT}件（ファイル名順・全尺）"
  fi
  echo ""
  echo "### 結果"
  echo "- 失敗: ambimux join exit $ec"
  echo "- 出力は作成されなかった可能性があります: $out_abs"
  exit "$ec"
fi
