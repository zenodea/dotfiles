#!/usr/bin/env bash
# herdr strips colour from status commands, so dirty shows as a trailing *.
dir="${HERDR_ACTIVE_PANE_CWD:-$PWD}"
name="$(basename "$dir")"
branch="$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null ||
  git -C "$dir" rev-parse --short HEAD 2>/dev/null)" || { printf '%s\n' "$name"; exit 0; }
[[ -n "$branch" ]] || { printf '%s\n' "$name"; exit 0; }
if git -C "$dir" diff --quiet --ignore-submodules HEAD 2>/dev/null; then
  printf '%s  %s\n' "$name" "$branch"
else
  printf '%s  %s*\n' "$name" "$branch"
fi
