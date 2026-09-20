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
    lum=$(((16#${bg:0:2} * 299 + 16#${bg:2:2} * 587 + 16#${bg:4:2} * 114) / 1000))
    appearance=dark
    ((lum > 127)) && appearance=light
    ((first)) || printf ','
    first=0
    printf '{"name":"%s","bg":"#%s","fg":"#%s","accent":"#%s","appearance":"%s"}' \
        "$name" "$bg" "$fg" "$accent" "$appearance"
done
printf ']\n'
