#!/usr/bin/env bash
# switch-theme.sh — render every app's config from a theme's palette, then
# live-reload whatever is running.
#
# Each app lives in apps/<general|mac|linux>/<name>.sh and defines:
#
#   render()                     write its config(s) from templates/
#   reload() | reload_<os>()     poke the running app (both optional)
#
# Apps under general/ run on every platform; mac/ and linux/ only run on
# theirs. A general app whose reload differs per OS defines reload_mac and
# reload_linux instead of reload. Each app is sourced in its own subshell, so
# helper functions and state stay local to it.
set -e

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEMES_DIR="$DOTFILES/themes"
TEMPLATES_DIR="$DOTFILES/templates"
APPS_DIR="$DOTFILES/apps"

case "$(uname -s)" in
    Darwin) PLATFORM="mac"   ;;
    Linux)  PLATFORM="linux" ;;
    *)      echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

# --- theme selection -------------------------------------------------------

list_themes() {
    local current=""
    [[ -f "$DOTFILES/.current-theme" ]] && current="$(cat "$DOTFILES/.current-theme")"

    echo "Available themes:"
    for f in "$THEMES_DIR"/*.sh; do
        local name
        name="$(basename "$f" .sh)"
        if [[ "$name" == "$current" ]]; then
            echo "  $name (active)"
        else
            echo "  $name"
        fi
    done
}

RELOAD=1
ARGS=()
for _arg in "$@"; do
    case "$_arg" in
        --no-reload) RELOAD=0 ;;
        *)           ARGS+=("$_arg") ;;
    esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

if [[ -z "${1:-}" || "$1" == "--list" || "$1" == "-l" ]]; then
    echo "Usage: switch-theme.sh <theme> [--no-reload]"
    echo ""
    list_themes
    exit 0
fi

THEME="$1"
THEME_FILE="$THEMES_DIR/$THEME.sh"

if [[ ! -f "$THEME_FILE" ]]; then
    echo "Error: theme '$THEME' not found"
    echo ""
    list_themes
    exit 1
fi

# --- palette ---------------------------------------------------------------

# Every color a theme defines. Each one also gets a <COLOR>_RGB ("r, g, b")
# form, derived below — some config formats want decimal channels.
PALETTE=(BG SURFACE BG_ALT BORDER FG FG_BRIGHT ACCENT BLUE RED GREEN YELLOW ORANGE PURPLE)

# Non-color fields a theme sets, plus the ones this script derives.
THEME_FIELDS=(NVIM_PLUGIN NVIM_COLORSCHEME ZED_THEME GHOSTTY_THEME VIFM_COLORSCHEME)
DERIVED=(THEME_NAME THEME_APPEARANCE ACCENT_H ACCENT_S ACCENT_L)

# shellcheck source=/dev/null
set -a
source "$THEME_FILE"
set +a

export THEME_NAME="$THEME"
export THEME_APPEARANCE="${APPEARANCE:-dark}"

for _c in "${PALETTE[@]}"; do
    _hex="${!_c}"
    printf -v "${_c}_RGB" '%d, %d, %d' \
        "$((16#${_hex:0:2}))" "$((16#${_hex:2:2}))" "$((16#${_hex:4:2}))"
    export "${_c}_RGB"
done

# Accent as HSL components (Obsidian's accent format)
ACCENT_H="" ACCENT_S="" ACCENT_L=""
if command -v python3 > /dev/null 2>&1; then
    read -r ACCENT_H ACCENT_S ACCENT_L <<< "$(python3 -c "
import colorsys
r, g, b = (int('$ACCENT'[i:i+2], 16) / 255 for i in (0, 2, 4))
h, l, s = colorsys.rgb_to_hls(r, g, b)
print(round(h * 360), round(s * 100), round(l * 100))")"
fi
export ACCENT_H ACCENT_S ACCENT_L

# --- template rendering ----------------------------------------------------

# Substitute only theme variables, so a literal $variable in a config file
# (waybar scripts, hyprland dispatchers) survives untouched.
VARS=""
for _v in "${PALETTE[@]}"; do VARS+="\${$_v}\${${_v}_RGB}"; done
for _v in "${THEME_FIELDS[@]}" "${DERIVED[@]}"; do VARS+="\${$_v}"; done

# envsubst ships with gettext, which stock macOS lacks — fall back to perl
if command -v envsubst &> /dev/null; then
    substitute() { envsubst "$VARS"; }
else
    substitute() {
        THEME_VARS="$VARS" perl -pe \
            's/\$\{(\w+)\}/(index($ENV{THEME_VARS}, "{$1}") >= 0 && defined $ENV{$1}) ? $ENV{$1} : $&/ge'
    }
fi

# --- helpers available to apps ---------------------------------------------

pretty() {
    local p="$1"
    p="${p#"$DOTFILES"/}"
    [[ "$p" == "$HOME"/* ]] && p="~${p#"$HOME"}"
    printf '%s' "$p"
}

note() { echo "    $1"; }
skip() { echo "    skipped: $1"; }
have() { command -v "$1" > /dev/null 2>&1; }

# generate <template-path-under-templates/> <destination>
generate() {
    local template="$TEMPLATES_DIR/$1" output="$2"
    mkdir -p "$(dirname "$output")"
    substitute < "$template" > "$output"
    note "wrote: $(pretty "$output")"
}

# copy <template-path-under-templates/> <destination>   (no substitution)
copy() {
    local template="$TEMPLATES_DIR/$1" output="$2"
    mkdir -p "$(dirname "$output")"
    cp "$template" "$output"
    note "wrote: $(pretty "$output")"
}

# --- run the apps ----------------------------------------------------------

echo "==> Switching to: $THEME"

for _dir in general "$PLATFORM"; do
    for _app in "$APPS_DIR/$_dir"/*.sh; do
        [[ -f "$_app" ]] || continue
        echo "  $(basename "$_app" .sh)"

        # The subshell must not be the operand of `||` or `if`: bash suppresses
        # errexit inside one, so a half-failed render would carry on to reload.
        # Drop errexit around the call instead, and check the status by hand.
        set +e
        (
            set -e
            # shellcheck source=/dev/null
            source "$_app"

            declare -f render > /dev/null && render

            [[ "$RELOAD" == 1 ]] || exit 0

            if declare -f "reload_$PLATFORM" > /dev/null; then
                "reload_$PLATFORM"
            elif declare -f reload > /dev/null; then
                reload
            fi
        )
        _status=$?
        set -e
        [[ "$_status" -eq 0 ]] || note "! failed (exit $_status)"
    done
done

echo "$THEME" > "$DOTFILES/.current-theme"

echo "==> Done. Active theme: $THEME"
