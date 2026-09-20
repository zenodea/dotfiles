#!/usr/bin/env bash

cache="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/updates"
max_age=1800

emit() {
    local stamp="$1" repo="$2" aur="$3" age=-1
    [[ -n "$stamp" ]] && age=$(($(date +%s) - stamp))
    printf '{"repo":%d,"aur":%d,"age":%d}\n' "${repo:-0}" "${aur:-0}" "$age"
}

lines() {
    printf '%s' "$1" | grep -c . || true
}

mkdir -p "$(dirname "$cache")"

stamp="" repo=0 aur=0
[[ -f "$cache" ]] && read -r stamp repo aur < "$cache"

emit "$stamp" "$repo" "$aur"

if [[ "$1" != "check" ]]; then
    [[ -n "$stamp" ]] && (($(date +%s) - stamp < max_age)) && exit 0
fi

command -v checkupdates > /dev/null 2>&1 || exit 0

out=$(timeout 40 checkupdates 2> /dev/null)
status=$?

case "$status" in
    0) repo=$(lines "$out") ;;
    2) repo=0 ;;
    *) exit 0 ;;
esac

aur=0
if command -v yay > /dev/null 2>&1; then
    out=$(timeout 40 yay -Qua 2> /dev/null) && aur=$(lines "$out")
fi

stamp=$(date +%s)
printf '%s %s %s\n' "$stamp" "$repo" "$aur" > "$cache"

emit "$stamp" "$repo" "$aur"
