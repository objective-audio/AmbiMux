#!/bin/bash
# Batch convert tagless VR180 MOV files to MV-HEVC
# Skips files already in MV-HEVC format (detected via ffprobe view_ids_available)
# Usage: ./convert-vr180.sh [sources_dir] [export_dir]
# Default: workspace/sbs-input/ → workspace/mux-input/

SOURCES="${1:-workspace/sbs-input}"
EXPORT="${2:-workspace/mux-input}"
PRESET="${PRESET:-PresetMVHEVC4320x4320}"

mkdir -p "$EXPORT"

is_mvhevc() {
  local view_ids
  view_ids=$(ffprobe -v error -select_streams v:0 -show_entries stream=view_ids_available \
    -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null)
  [[ "$view_ids" == *"0,1"* ]]
}

for f in "$SOURCES"/*.mov; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .mov)
  out="$EXPORT/${name}.mov"

  if is_mvhevc "$f"; then
    echo "Already MV-HEVC, skipping: $name"
  else
    echo "Converting: $name"
    avconvert -s "$f" -o "$out" -p "$PRESET" \
      --sourceProjection HalfEquirectangular \
      --sourceViewPacking SideBySide \
      --replace --progress
  fi
done
