#!/usr/bin/env bash

repo="$(cd -P "$(dirname "$0")" && cd ../../../../.. && pwd)"
src="$repo/wallpapers/full-size"
previews="$repo/wallpapers/previews"

for f in "$src"/*; do
    [[ -f "$f" ]] || continue
    name=$(basename "$f")
    case "${name,,}" in
        *.png | *.jpg | *.jpeg | *.webp | *.avif | *.bmp | *.gif) ;;
        *) continue ;;
    esac

    preview="$previews/${name%.*}.jpg"
    if [[ -s "$preview" ]]; then
        printf '%s\t%s\n' "$name" "$preview"
    else
        printf '%s\t%s\n' "$name" "$f"
    fi
done
