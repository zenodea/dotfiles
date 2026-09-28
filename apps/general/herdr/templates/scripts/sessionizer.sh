#!/usr/bin/env bash
set -e

herdr="${HERDR_BIN_PATH:-herdr}"
workspaces="$("$herdr" workspace list)"

id_of() {
  jq -r --arg n "$1" '.result.workspaces[] | select(.label == $n) | .workspace_id' <<<"$workspaces" | head -n1
}

dirs() {
  jq -r '.result.workspaces[].label' <<<"$workspaces" | sed 's/^/  /'
  for d in "$HOME/dotfiles" "$HOME/scripts"; do [[ -d "$d" ]] && echo "$d"; done
  find "$HOME/Projects" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort
}

pick="$(dirs | sed "s|^$HOME|~|" | fzf --prompt='workspace › ' --no-info --reverse \
  --color="bg:-1,bg+:-1,fg:#${FG},fg+:#${FG_BRIGHT},hl:#${ACCENT},hl+:#${ACCENT},prompt:#${ACCENT},pointer:#${ACCENT}")"
[[ -n "$pick" ]] || exit 0

if [[ "$pick" == "  "* ]]; then
  name="${pick#  }"
  dir=""
else
  dir="${pick/#\~/$HOME}"
  name="$(basename "$dir")"
fi

id="$(id_of "$name")"
if [[ -n "$id" ]]; then
  "$herdr" workspace focus "$id" >/dev/null
elif [[ -n "$dir" ]]; then
  "$herdr" workspace create --cwd "$dir" --label "$name" --focus >/dev/null
fi
