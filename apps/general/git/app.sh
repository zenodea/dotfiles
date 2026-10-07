render() {
  local bat; bat="$(command -v bat || command -v batcat)" || return 0
  local dir; dir="$("$bat" --config-dir)"
  mkdir -p "$dir/themes"
  substitute < "$DOTFILES/themes/templates/dotfiles.tmTheme" > "$dir/themes/dotfiles.tmTheme"
  "$bat" cache --build >/dev/null
  printf '%s\n' '--theme="dotfiles"' '--italic-text=always' > "$dir/config"
  note "wrote: $(pretty "$dir/themes/dotfiles.tmTheme"), rebuilt bat's cache"
}
