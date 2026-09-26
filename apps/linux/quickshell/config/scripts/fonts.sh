#!/usr/bin/env bash

repo="$(cd -P "$(dirname "$0")" && cd ../../../../.. && pwd)"

printf '['
first=1
for f in "$repo"/fonts/*.sh; do
    [[ -f "$f" ]] || continue
    name=$(basename "$f" .sh)
    mono=$(sed -n 's/^FONT_MONO_FAMILY="\([^"]*\)".*/\1/p' "$f" | head -1)
    text=$(sed -n 's/^FONT_TEXT_FAMILY="\([^"]*\)".*/\1/p' "$f" | head -1)
    title=$(sed -n '2s/^# \(.*\) — .*/\1/p; 2s/^# \([^—]*\)$/\1/p' "$f" | head -1)
    installed=false
    [[ -n "$mono" ]] && fc-list -q "$mono" && installed=true
    ((first)) || printf ','
    first=0
    printf '{"name":"%s","title":"%s","mono":"%s","text":"%s","installed":%s}' \
        "$name" "${title:-$name}" "$mono" "$text" "$installed"
done
printf ']\n'
