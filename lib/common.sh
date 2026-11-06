# Shared by install.sh, switch-theme and bin/dotfiles.
# Expects $DOTFILES to be set to the repo root before sourcing.

case "$(uname -s)" in
Darwin) PLATFORM="mac" ;;
Linux) PLATFORM="linux" ;;
*)
  echo "Unsupported OS: $(uname -s)" >&2
  exit 1
  ;;
esac

# Theme reloads shell out to GUI tools (sketchybar, borders, aerospace) that
# live in Homebrew's bin. Interactive shells have that on PATH, but launchd
# (the auto-appearance timer) and Raycast do not — there the reloads would be
# command-not-found and fail silently, leaving the bar on stale colors. Put the
# usual bin dirs on PATH up front so any caller's reloads resolve.
for _d in /opt/homebrew/bin /usr/local/bin; do
  case ":$PATH:" in
  *":$_d:"*) ;;
  *) [[ -d "$_d" ]] && PATH="$_d:$PATH" ;;
  esac
done
export PATH
unset _d

# sketchybar-msg aborts with "'env USER' not set!" when USER is missing, which
# it is under launchd (the auto-appearance timer) and Raycast. Guarantee it so
# the sketchybar reload doesn't fail for those callers.
export USER="${USER:-$(id -un)}"

have() { command -v "$1" >/dev/null 2>&1; }

# Every theme in accent-color order, so pickers read as a spectrum: red first,
# round the wheel, grey accents last. A light half sorts with its dark half,
# straight after it. One awk pass over all files keeps this cheap.
theme_names() {
  awk '
    function hex(s, i) { return index("0123456789abcdef", tolower(substr(s, i, 1))) * 16 + index("0123456789abcdef", tolower(substr(s, i + 1, 1))) - 17 }
    function hue(c,   r, g, b, mx, mn, d, h) {
      r = hex(c, 1); g = hex(c, 3); b = hex(c, 5)
      mx = r; if (g > mx) mx = g; if (b > mx) mx = b
      mn = r; if (g < mn) mn = g; if (b < mn) mn = b
      d = mx - mn
      if (d < 20) return -1
      if (mx == r) h = (g - b) / d
      else if (mx == g) h = (b - r) / d + 2
      else h = (r - g) / d + 4
      return (h * 60 + 360 + 15) % 360 # +15 keeps crimson next to red
    }
    FNR == 1 { n = FILENAME; sub(/.*\//, "", n); sub(/\.sh$/, "", n); names[n] = 1 }
    /^ACCENT="[0-9a-fA-F]+"/ { split($0, kv, "\""); accent[n] = kv[2] }
    END {
      for (n in names) {
        key[n] = hue(accent[n]); if (key[n] < 0) key[n] = 999
      }
      for (n in names) {
        base = n; light = sub(/-light$/, "", base)
        if (!(base in names)) base = n
        printf "%07.2f\t%s\t%d\t%s\n", key[base], base, light, n
      }
    }' "$DOTFILES/themes"/*.sh | sort -t "$(printf '\t')" -k1,1n -k2,2 -k3,3n | cut -f4
}

current_theme() {
  cat "$DOTFILES/.current-theme" 2>/dev/null || true
}

# --- fonts -------------------------------------------------------------------

# Fonts mirror themes: fonts/<name>.sh presets
DEFAULT_FONT="berkeley-mono"

font_names() {
  local f
  for f in "$DOTFILES/fonts"/*.sh; do
    basename "$f" .sh
  done
}

font_exists() { [[ -f "$DOTFILES/fonts/$1.sh" ]]; }

current_font() {
  local f
  f="$(cat "$DOTFILES/.current-font" 2>/dev/null)"
  [[ -n "$f" ]] && font_exists "$f" || f="$DEFAULT_FONT"
  printf '%s' "$f"
}

text_font_names() {
  local f
  for f in "$DOTFILES/fonts/text"/*.sh; do
    basename "$f" .sh
  done
}

text_font_exists() { [[ -f "$DOTFILES/fonts/text/$1.sh" ]]; }

# Empty when unset: the mono preset's own FONT_TEXT_FAMILY applies.
current_text_font() {
  local f
  f="$(cat "$DOTFILES/.current-text-font" 2>/dev/null)"
  if text_font_exists "$f"; then printf '%s' "$f"; fi
}

# --- light / dark ----------------------------------------------------------

# Light or dark is a fact about the palette, so read it off the background's
# perceived brightness (ITU-R BT.601) rather than keeping a field in sync.
appearance_of() { # appearance_of <rrggbb>
  local hex="$1" lum
  lum=$(((16#${hex:0:2} * 299 + 16#${hex:2:2} * 587 + 16#${hex:4:2} * 114) / 1000))
  if [[ $lum -gt 127 ]]; then echo light; else echo dark; fi
}

theme_exists() { [[ -f "$DOTFILES/themes/$1.sh" ]]; }

# Read one field out of a theme without loading it — subshell, so the palette
# doesn't leak into the caller.
theme_field() { # theme_field <theme> <field>
  theme_exists "$1" || return 1
  (
    source "$DOTFILES/themes/$1.sh" >/dev/null 2>&1
    printf '%s' "${!2}"
  )
}

theme_appearance() { # theme_appearance <theme>
  local bg
  bg="$(theme_field "$1" BG)" || return 1
  [[ -n "$bg" ]] || return 1
  appearance_of "$bg"
}

# A pair is a name plus a convention: dark is the base name, light carries a
# -light suffix (gruvbox ↔ gruvbox-light). Nothing to store, nothing to sync.
theme_base() { printf '%s' "${1%-light}"; }

theme_variant() { # theme_variant <theme> <light|dark>
  case "$2" in
  light) printf '%s-light' "$(theme_base "$1")" ;;
  *) theme_base "$1" ;;
  esac
}

theme_paired() { # both halves exist, and are what they claim
  local base
  base="$(theme_base "$1")"
  theme_exists "$base" && theme_exists "$base-light" &&
    [[ "$(theme_appearance "$base")" == "dark" ]] &&
    [[ "$(theme_appearance "$base-light")" == "light" ]]
}

# --- auto mode -------------------------------------------------------------

# .auto-theme holds the pair's base name; its presence is what turns auto mode
# on. .auto-pin holds the appearance in effect at the last manual pick, so that
# pick survives until the next light/dark boundary instead of the next tick.
AUTO_FILE="$DOTFILES/.auto-theme"
PIN_FILE="$DOTFILES/.auto-pin"

auto_enabled() { [[ -f "$AUTO_FILE" ]]; }
auto_base() { cat "$AUTO_FILE" 2>/dev/null || true; }
auto_pin() { cat "$PIN_FILE" 2>/dev/null || true; }

# macOS tracks light/dark itself — and follows real sunrise/sunset when
# Appearance is Auto — so defer to it instead of keeping a second schedule.
# Linux has no such setting, so go by the clock.
desired_appearance() {
  case "$PLATFORM" in
  mac)
    if [[ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" == "Dark" ]]; then
      echo dark
    else
      echo light
    fi
    ;;
  linux)
    local hour
    hour=$((10#$(date +%H)))
    if ((hour >= ${DOTFILES_DAY_START:-7} && hour < ${DOTFILES_DAY_END:-19})); then
      echo light
    else
      echo dark
    fi
    ;;
  esac
}
