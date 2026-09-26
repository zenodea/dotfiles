#!/usr/bin/env bash

repo="$(cd -P "$(dirname "$0")" && cd ../../../../.. && pwd)"

printf '['
first=1
for f in "$repo"/fonts/text/*.sh; do
    [[ -f "$f" ]] || continue
    name=$(basename "$f" .sh)
    family=$(sed -n 's/^FONT_TEXT_FAMILY="\([^"]*\)".*/\1/p' "$f" | head -1)
    title=$(sed -n '2s/^# \(.*\) — .*/\1/p; 2s/^# \([^—]*\)$/\1/p' "$f" | head -1)
    installed=false
    [[ -n "$family" ]] && fc-list -q "$family" && installed=true
    ((first)) || printf ','
    first=0
    printf '{"name":"%s","title":"%s","family":"%s","installed":%s}' "$name" "${title:-$name}" "$family" "$installed"
done
printf ']\n'
