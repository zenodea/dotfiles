render() {
  generate config.toml "$HOME/.config/herdr/config.toml"
  local s
  for s in git sessionizer; do
    generate "scripts/$s.sh" "$HOME/.config/herdr/scripts/$s.sh"
    chmod +x "$HOME/.config/herdr/scripts/$s.sh"
  done
  plugins
}

# Install whatever plugins.txt lists and herdr doesn't have yet. A plugin that
# is already registered is left alone, including a locally linked checkout.
plugins() {
  local list="$APP_DIR/plugins.txt"
  [[ -f "$list" ]] && have herdr || return 0
  local installed id src
  installed="$(herdr plugin list 2>/dev/null)" || return 0
  while read -r id src; do
    [[ -z "$id" || "$id" == \#* ]] && continue
    grep -q "^- $id " <<<"$installed" && continue
    if herdr plugin install "$src" --yes >/dev/null 2>&1; then
      note "installed plugin: $id"
    else
      note "plugin install failed: $id ($src)"
    fi
  done <"$list"
}

reload() {
  have herdr || return 0
  herdr server reload-config >/dev/null 2>&1 || return 0
  note "reloaded"
}
