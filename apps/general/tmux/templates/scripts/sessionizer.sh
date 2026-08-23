#!/usr/bin/env bash
set -e

dirs() {
  tmux list-sessions -F '#{session_name}' 2>/dev/null |
    grep -vxE 'lazygit|codex|claude' | sed 's/^/  /'
  for d in "$HOME/dotfiles" "$HOME/scripts"; do [[ -d "$d" ]] && echo "$d"; done
  find "$HOME/Projects" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort
}

pick="$(dirs | sed "s|^$HOME|~|" | fzf --prompt='session › ' --no-info --reverse \
  --color="bg:-1,bg+:-1,fg:#${FG},fg+:#${FG_BRIGHT},hl:#${ACCENT},hl+:#${ACCENT},prompt:#${ACCENT},pointer:#${ACCENT}")"
[[ -n "$pick" ]] || exit 0

if [[ "$pick" == "  "* ]]; then
  name="${pick#  }"
else
  dir="${pick/#\~/$HOME}"
  name="$(basename "$dir" | tr '.:' '__')"
  tmux has-session -t "=$name" 2>/dev/null || tmux new-session -ds "$name" -c "$dir"
fi
tmux switch-client -t "=$name"
