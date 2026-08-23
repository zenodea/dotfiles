#!/usr/bin/env bash
dir="${1:-.}"
branch="$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null ||
  git -C "$dir" rev-parse --short HEAD 2>/dev/null)" || exit 0
[[ -n "$branch" ]] || exit 0
if git -C "$dir" diff --quiet --ignore-submodules HEAD 2>/dev/null; then
  printf ' #[fg=#%s] %s' "${GREEN}" "$branch"
else
  printf ' #[fg=#%s] %s*' "${ORANGE}" "$branch"
fi
