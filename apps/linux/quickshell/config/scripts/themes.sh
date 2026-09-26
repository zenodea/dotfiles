#!/usr/bin/env bash

repo="$(cd -P "$(dirname "$0")" && cd ../../../../.. && pwd)"

field() { sed -n "s/^$2=\"\([^\"]*\)\".*/\1/p" "$1" | head -1; }

printf '['
first=1
for f in "$repo"/themes/*.sh; do
    [[ -f "$f" ]] || continue
    name=$(basename "$f" .sh)
    bg=$(field "$f" BG)
    fg=$(field "$f" FG)
    accent=$(field "$f" ACCENT)
    [[ -z "$bg" ]] && continue
    colors=""
    for key in SURFACE RED GREEN YELLOW BLUE PURPLE ORANGE; do
        colors+=$(printf ',"%s":"#%s"' "${key,,}" "$(field "$f" "$key")")
    done
    wall=$(field "$f" WALLPAPER)
    thumb=""
    if [[ -s "$repo/wallpapers/previews/${wall%.*}.jpg" ]]; then
        thumb="file://$repo/wallpapers/previews/${wall%.*}.jpg"
    elif [[ -n "$wall" && -f "$repo/wallpapers/full-size/$wall" ]]; then
        thumb="file://$repo/wallpapers/full-size/$wall"
    fi
    lum=$(((16#${bg:0:2} * 299 + 16#${bg:2:2} * 587 + 16#${bg:4:2} * 114) / 1000))
    appearance=dark
    ((lum > 127)) && appearance=light
    ((first)) || printf ','
    first=0
    printf '{"name":"%s","bg":"#%s","fg":"#%s","accent":"#%s","appearance":"%s","thumb":"%s"%s}' \
        "$name" "$bg" "$fg" "$accent" "$appearance" "$thumb" "$colors"
done
printf ']\n'
