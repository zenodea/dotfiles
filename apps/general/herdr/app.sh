render() {
  generate config.toml "$HOME/.config/herdr/config.toml"
  local s
  for s in git sessionizer; do
    generate "scripts/$s.sh" "$HOME/.config/herdr/scripts/$s.sh"
    chmod +x "$HOME/.config/herdr/scripts/$s.sh"
  done
}

reload() {
  have herdr || return 0
  herdr server reload-config >/dev/null 2>&1 || return 0
  note "reloaded"
}
