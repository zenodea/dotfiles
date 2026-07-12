#!/usr/bin/env bash
# Alfred action — runs the selected dotfiles command.
#
# Reads `cmd` / `value` / `output_style` from the workflow variables set by
# filter.sh. Prints the text that the Large Type / Notification output shows.
set -uo pipefail
source "$(dirname "$0")/common.sh"

cmd="${cmd:-}"
value="${value:-}"
output_style="${output_style:-notification}"

[ -n "$cmd" ] || { echo "No command given"; exit 1; }

if [ -n "$value" ]; then
    output="$("$DF" "$cmd" "$value" 2>&1)"
else
    output="$("$DF" "$cmd" 2>&1)"
fi
status=$?

# The CLI colourises for a TTY only, but doctor's glyphs still come through.
output="$(printf '%s' "$output" | sed -E $'s/\033\\[[0-9;]*m//g')"
last_line="$(printf '%s\n' "$output" | grep -v '^[[:space:]]*$' | tail -n 1)"

if [ "$output_style" = "largetype" ]; then
    printf '%s\n' "${output:-done}"
    exit 0
fi

if [ $status -ne 0 ]; then
    printf 'Failed: %s\n' "${last_line:-$cmd exited $status}"
    exit 0
fi

case "$cmd" in
    --theme)  printf 'Theme → %s\n' "$value" ;;
    --random) printf 'Theme → %s\n' "$("$DF" --current)" ;;
    --save)   printf '%s\n' "${last_line:-Saved}" ;;
    *)        printf '%s\n' "${last_line:-done}" ;;
esac
