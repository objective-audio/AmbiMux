#!/usr/bin/env bash
# Batch attenuate: lower APAC Ambisonics level per MOV listed in attenuate.txt.
# Invokes repository .build/release/ambimux attenuate. Run from repo root or anywhere.
#
# Usage: batch-attenuate.sh [input_dir] [output_dir] [repo_root]
# Defaults: workspace/attenuate-input  workspace/attenuate-output  (repo root = 4 levels up from this script)
#
# input_dir/attenuate.txt is required. Each line is basename.mov@DB (DB = --db, 0 or positive).
# Unlisted .mov files are ignored.
#
# Environment:
#   BATCH_ATTENUATE_SKIP_BUILD=1  — skip "swift build -c release" (not recommended; matches SKILL when unset)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

INPUT_DIR="${1:-workspace/attenuate-input}"
OUTPUT_DIR="${2:-workspace/attenuate-output}"
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

is_nonneg_number() {
  [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

mkdir -p "$OUTPUT_DIR"

if [[ ! -d "$INPUT_DIR" ]]; then
  echo "error: input directory does not exist: $INPUT_DIR" >&2
  exit 1
fi

INPUT_DIR_ABS="$(cd "$INPUT_DIR" && pwd)"
ATTENUATE_TXT="$INPUT_DIR_ABS/attenuate.txt"

if [[ ! -f "$ATTENUATE_TXT" ]]; then
  echo "error: attenuate.txt is required: $ATTENUATE_TXT" >&2
  exit 1
fi

if [[ -z "${BATCH_ATTENUATE_SKIP_BUILD:-}" ]]; then
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

FILE_PARTS=()
DBS=()
MOV_ABSES=()
DISPLAY_SPECS=()

line_no=0
while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  line_no=$((line_no + 1))
  line="${raw_line#"${raw_line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" ]] && continue
  [[ "$line" == \#* ]] && continue

  if [[ "$line" == *" "* || "$line" == *$'\t'* ]]; then
    echo "error: attenuate.txt line $line_no has whitespace (filenames with spaces are not supported): $line" >&2
    exit 1
  fi

  if [[ "$line" == */* ]]; then
    echo "error: attenuate.txt line $line_no must be a basename under the input dir (no subdirectories): $line" >&2
    exit 1
  fi

  if [[ "$line" != *@* ]]; then
    echo "error: attenuate.txt line $line_no must be basename.mov@DB: $line" >&2
    exit 1
  fi

  file_part="${line%@*}"
  db_part="${line##*@}"

  if [[ -z "$file_part" || "$file_part" == "$line" ]]; then
    echo "error: attenuate.txt line $line_no must be basename.mov@DB: $line" >&2
    exit 1
  fi

  if [[ "$file_part" != *.mov ]]; then
    echo "error: attenuate.txt line $line_no must refer to a .mov file: $line" >&2
    exit 1
  fi

  if ! is_nonneg_number "$db_part"; then
    echo "error: attenuate.txt line $line_no DB must be 0 or positive (same as --db): $line" >&2
    exit 1
  fi

  if ((${#FILE_PARTS[@]} > 0)); then
    for existing in "${FILE_PARTS[@]}"; do
      if [[ "$existing" == "$file_part" ]]; then
        echo "error: attenuate.txt line $line_no duplicates $file_part (output would collide)" >&2
        exit 1
      fi
    done
  fi

  mov_path="$INPUT_DIR_ABS/$file_part"
  if [[ ! -f "$mov_path" ]]; then
    echo "error: attenuate.txt line $line_no: file not found: $mov_path" >&2
    exit 1
  fi

  FILE_PARTS+=("$file_part")
  DBS+=("$db_part")
  MOV_ABSES+=("$(abs_path "$mov_path")")
  DISPLAY_SPECS+=("$line")
done <"$ATTENUATE_TXT"

ENTRY_COUNT="${#FILE_PARTS[@]}"

if ((ENTRY_COUNT == 0)); then
  echo "error: attenuate.txt has no entries: $ATTENUATE_TXT" >&2
  exit 1
fi

echo ""
echo "==> Attenuating ${ENTRY_COUNT} clips (attenuate.txt order)"
echo "    manifest: $ATTENUATE_TXT"
for spec in "${DISPLAY_SPECS[@]}"; do
  echo "  - $spec"
done
echo "==> Output dir: $(abs_path "$OUTPUT_DIR")"
echo ""

success=0
fail=0
declare -a SUCCESS_ENTRIES FAIL_ENTRIES

i=0
while ((i < ENTRY_COUNT)); do
  file_part="${FILE_PARTS[$i]}"
  db_part="${DBS[$i]}"
  mov_abs="${MOV_ABSES[$i]}"
  display="${DISPLAY_SPECS[$i]}"
  base="$(basename "$file_part" .mov)"
  out_raw="$OUTPUT_DIR/${base}_attenuated.mov"
  out_abs="$(abs_path "$out_raw")"

  echo ""
  echo "---- $base ----"
  echo "  db: $db_part"
  echo "  output: $out_abs"

  if "$AMBIMUX" attenuate "$mov_abs" --db "$db_part" --output "$out_abs"; then
    ((success += 1)) || true
    SUCCESS_ENTRIES+=("$display → $out_abs")
  else
    ec=$?
    ((fail += 1)) || true
    FAIL_ENTRIES+=("$display (エラー: ambimux attenuate exit $ec)")
  fi

  i=$((i + 1))
done

echo ""
echo "## 処理結果サマリ"
echo ""
echo "### 入力"
echo "- モード: attenuate.txt マニフェスト"
echo "- エントリ: ${ENTRY_COUNT}件（行順）"
for spec in "${DISPLAY_SPECS[@]}"; do
  echo "  - $spec"
done
echo ""
echo "### 結果"
echo "- 成功: ${success}件"
echo "- 失敗: ${fail}件"

if ((success > 0)); then
  echo ""
  echo "成功した変換:"
  for e in "${SUCCESS_ENTRIES[@]}"; do
    echo "- $e"
  done
fi

if ((fail > 0)); then
  echo ""
  echo "失敗した変換:"
  for e in "${FAIL_ENTRIES[@]}"; do
    echo "- $e"
  done
  exit 1
fi

exit 0
