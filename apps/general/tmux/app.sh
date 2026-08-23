render() {
  # a dangling ~/.tmux.conf (old symlink) would shadow the rendered file
  if [[ -L "$HOME/.tmux.conf" && ! -e "$HOME/.tmux.conf" ]]; then
    rm "$HOME/.tmux.conf"
    note "removed dangling ~/.tmux.conf"
  fi
  generate tmux.conf "$HOME/.config/tmux/tmux.conf"
  local s
  for s in git popups sessionizer; do
    generate "scripts/$s.sh" "$HOME/.config/tmux/scripts/$s.sh"
    chmod +x "$HOME/.config/tmux/scripts/$s.sh"
  done
}

reload() {
  tmux has-session >/dev/null 2>&1 || return 0
  tmux source-file "$HOME/.config/tmux/tmux.conf"
  note "reloaded"
}
