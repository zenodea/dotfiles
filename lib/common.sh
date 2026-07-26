# Shared by install.sh, switch-theme and bin/dotfiles.
# Expects $DOTFILES to be set to the repo root before sourcing.

case "$(uname -s)" in
    Darwin) PLATFORM="mac"   ;;
    Linux)  PLATFORM="linux" ;;
    *)      echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

have() { command -v "$1" > /dev/null 2>&1; }

theme_names() {
    local f
    for f in "$DOTFILES/themes"/*.sh; do
        basename "$f" .sh
    done
}

current_theme() {
    cat "$DOTFILES/.current-theme" 2>/dev/null || true
}

# --- light / dark ----------------------------------------------------------

# Light or dark is a fact about the palette, so read it off the background's
# perceived brightness (ITU-R BT.601) rather than keeping a field in sync.
appearance_of() {                       # appearance_of <rrggbb>
    local hex="$1" lum
    lum=$(( (16#${hex:0:2} * 299 + 16#${hex:2:2} * 587 + 16#${hex:4:2} * 114) / 1000 ))
    if [[ $lum -gt 127 ]]; then echo light; else echo dark; fi
}

theme_exists() { [[ -f "$DOTFILES/themes/$1.sh" ]]; }

# Read one field out of a theme without loading it — subshell, so the palette
# doesn't leak into the caller.
theme_field() {                         # theme_field <theme> <field>
    theme_exists "$1" || return 1
    (source "$DOTFILES/themes/$1.sh" > /dev/null 2>&1; printf '%s' "${!2}")
}

theme_appearance() {                    # theme_appearance <theme>
    local bg
    bg="$(theme_field "$1" BG)" || return 1
    [[ -n "$bg" ]] || return 1
    appearance_of "$bg"
}

# A pair is a name plus a convention: dark is the base name, light carries a
# -light suffix (gruvbox ↔ gruvbox-light). Nothing to store, nothing to sync.
theme_base()  { printf '%s' "${1%-light}"; }

theme_variant() {                       # theme_variant <theme> <light|dark>
    case "$2" in
        light) printf '%s-light' "$(theme_base "$1")" ;;
        *)     theme_base "$1" ;;
    esac
}

theme_paired() {                        # both halves exist, and are what they claim
    local base; base="$(theme_base "$1")"
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
auto_base()    { cat "$AUTO_FILE" 2>/dev/null || true; }
auto_pin()     { cat "$PIN_FILE"   2>/dev/null || true; }

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
            if (( hour >= ${DOTFILES_DAY_START:-7} && hour < ${DOTFILES_DAY_END:-19} )); then
                echo light
            else
                echo dark
            fi
            ;;
    esac
}
