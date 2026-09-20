#!/usr/bin/env bash

repo="$(cd -P "$(dirname "$0")" && cd ../../../../.. && pwd)"
src="$repo/wallpapers"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/wallpaper-thumbs"
mkdir -p "$cache"

make_thumb() {
    local file=$1 out=$2
    if command -v vipsthumbnail > /dev/null 2>&1; then
        vipsthumbnail "$file" --size 320x -o "$out[Q=82]" 2> /dev/null && [[ -s "$out" ]] && return 0
    fi
    if command -v magick > /dev/null 2>&1; then
        magick "$file" -resize 320x -quality 82 "$out" 2> /dev/null && [[ -s "$out" ]] && return 0
    fi
    return 1
}

for f in "$src"/*; do
    [[ -f "$f" ]] || continue
    name=$(basename "$f")
    case "${name,,}" in
        *.png | *.jpg | *.jpeg | *.webp | *.avif | *.bmp | *.gif) ;;
        *) continue ;;
    esac

    out="$cache/${name%.*}.jpg"
    [[ -s "$out" && ! "$f" -nt "$out" ]] || make_thumb "$f" "$out"

    if [[ -s "$out" ]]; then
        printf '%s\t%s\n' "$name" "$out"
    else
        printf '%s\t%s\n' "$name" "$f"
    fi
done
