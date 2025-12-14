#!/usr/bin/env bash

DIR="$HOME/Pictures/Wallpapers"
STATE="${XDG_CACHE_HOME:-$HOME/.cache}/swww-index"

mkdir -p "$(dirname "$STATE")"

# Collect images in a stable order
mapfile -t FILES < <(find "$DIR" -maxdepth 1 -type f \
  \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) \
  | sort)

[ ${#FILES[@]} -eq 0 ] && exit 1

# Read previous index (default 0)
if [[ -f "$STATE" ]]; then
  IDX=$(<"$STATE")
else
  IDX=0
fi

# Advance and wrap
IDX=$(( (IDX + 1) % ${#FILES[@]} ))
echo "$IDX" > "$STATE"

# Set wallpaper with a nice transition
swww img "${FILES[$IDX]}" \
  --transition-type fade \
  --transition-step 20 \
  --transition-fps 120
