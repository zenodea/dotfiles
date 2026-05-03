#!/usr/bin/env bash
set -e

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEMES_DIR="$DOTFILES/themes"
TEMPLATES_DIR="$DOTFILES/templates"

# List available themes
list_themes() {
    echo "Available themes:"
    for f in "$THEMES_DIR"/*.sh; do
        local name
        name="$(basename "$f" .sh)"
        if [[ -f "$DOTFILES/.current-theme" ]] && [[ "$(cat "$DOTFILES/.current-theme")" == "$name" ]]; then
            echo "  $name (active)"
        else
            echo "  $name"
        fi
    done
}

if [[ -z "$1" || "$1" == "--list" || "$1" == "-l" ]]; then
    echo "Usage: switch-theme.sh <theme>"
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

# shellcheck source=/dev/null
set -a
source "$THEME_FILE"
set +a

WALLPAPER_PATH="$DOTFILES/Wallpapers/$WALLPAPER"

# Only substitute theme variables, not any $variable references inside config files
VARS='${BG}${SURFACE}${BG_ALT}${BORDER}${FG}${FG_BRIGHT}${ACCENT}${BLUE}${RED}${GREEN}${YELLOW}${ORANGE}${PURPLE}${FG_RGB}${BG_RGB}${SURFACE_RGB}${BG_ALT_RGB}${ACCENT_RGB}${BLUE_RGB}${RED_RGB}${GREEN_RGB}${NVIM_PLUGIN}${NVIM_COLORSCHEME}${ZED_THEME}${GHOSTTY_THEME}${VIFM_COLORSCHEME}${WALLPAPER_PATH}'

generate() {
    local template="$1"
    local output="$2"
    envsubst "$VARS" < "$template" > "$output"
    echo "  wrote: $(realpath --relative-to="$DOTFILES" "$output")"
}

echo "==> Switching to: $THEME"

# Hyprland
generate "$TEMPLATES_DIR/hypr/hyprland.conf"    "$DOTFILES/linux/config/hypr/hyprland.conf"
generate "$TEMPLATES_DIR/hypr/hyprlock.conf"    "$DOTFILES/linux/config/hypr/hyprlock.conf"

# Waybar
generate "$TEMPLATES_DIR/waybar/style.css"      "$DOTFILES/linux/config/waybar/style.css"

# Fuzzel
generate "$TEMPLATES_DIR/fuzzel/fuzzel.ini"     "$DOTFILES/linux/config/fuzzel/fuzzel.ini"

# Rofi
generate "$TEMPLATES_DIR/rofi/theme.rasi"       "$DOTFILES/linux/local/share/rofi/themes/current.rasi"

# macOS Sketchybar
generate "$TEMPLATES_DIR/sketchybar/colors.sh"  "$DOTFILES/mac/sketchybar/colors.sh"

# Neovim — not symlinked, write to dotfiles path + live config if it exists
generate "$TEMPLATES_DIR/nvim/colorscheme.lua"  "$DOTFILES/general/nvim/lua/plugins/colorscheme.lua"
if [[ -d "$HOME/.config/nvim/lua/plugins" ]]; then
    cp "$DOTFILES/general/nvim/lua/plugins/colorscheme.lua" "$HOME/.config/nvim/lua/plugins/colorscheme.lua"
    echo "  wrote: ~/.config/nvim/lua/plugins/colorscheme.lua"
fi

# Zed — write to dotfiles path + live config (Zed on Linux reads ~/.config/zed/)
generate "$TEMPLATES_DIR/zed/settings.json"     "$DOTFILES/general/zed/settings.json"
if [[ -f "$HOME/.config/zed/settings.json" ]]; then
    cp "$DOTFILES/general/zed/settings.json" "$HOME/.config/zed/settings.json"
    echo "  wrote: ~/.config/zed/settings.json"
fi

# Ghostty — write directly to live config (not in dotfiles install)
generate "$TEMPLATES_DIR/ghostty/config"        "$HOME/.config/ghostty/config"

# vifm colorscheme include
generate "$TEMPLATES_DIR/vifm/theme.vifm"       "$DOTFILES/linux/config/vifm/theme.vifm"

# macOS borders
generate "$TEMPLATES_DIR/borders/bordersrc"     "$DOTFILES/mac/borders/bordersrc"

# macOS Sketchybar (rc file)
generate "$TEMPLATES_DIR/sketchybar/sketchybarrc" "$DOTFILES/mac/sketchybar/sketchybarrc"

# Rofi power menu + theme picker
generate "$TEMPLATES_DIR/rofi/power-menu.rasi"   "$DOTFILES/linux/local/share/rofi/themes/power-menu.rasi"
generate "$TEMPLATES_DIR/rofi/theme-picker.rasi" "$DOTFILES/linux/local/share/rofi/themes/theme-picker.rasi"

# Firefox userChrome.css
FIREFOX_PROFILE_DIR=""
if [[ -f "$HOME/.mozilla/firefox/profiles.ini" ]]; then
    _ff_rel=$(awk '/^\[Install/{found=1; next} found && /^Default=/{sub(/^Default=/, ""); print; exit}' \
        "$HOME/.mozilla/firefox/profiles.ini" 2>/dev/null)
    if [[ -n "$_ff_rel" ]]; then
        FIREFOX_PROFILE_DIR="$HOME/.mozilla/firefox/$_ff_rel"
    fi
fi
if [[ -n "$FIREFOX_PROFILE_DIR" && -d "$FIREFOX_PROFILE_DIR" ]]; then
    mkdir -p "$FIREFOX_PROFILE_DIR/chrome"
    generate "$TEMPLATES_DIR/firefox/userChrome.css"   "$FIREFOX_PROFILE_DIR/chrome/userChrome.css"
    generate "$TEMPLATES_DIR/firefox/userContent.css"  "$FIREFOX_PROFILE_DIR/chrome/userContent.css"
    # Ensure required prefs are set: userChrome.css + force dark mode
    _userjs="$FIREFOX_PROFILE_DIR/user.js"
    _set_pref() {
        local key="$1" val="$2"
        if grep -q "\"$key\"" "$_userjs" 2>/dev/null; then
            # Replace existing line in place
            sed -i "s|user_pref(\"$key\",.*);|user_pref(\"$key\", $val);|" "$_userjs"
        else
            echo "user_pref(\"$key\", $val);" >> "$_userjs"
        fi
    }
    _set_pref "toolkit.legacyUserProfileCustomizations.stylesheets" "true"
    _set_pref "ui.systemUsesDarkTheme"                              "1"
    _set_pref "layout.css.prefers-color-scheme.content-override"    "0"
    _set_pref "browser.theme.content-theme"                         "0"
    _set_pref "browser.theme.toolbar-theme"                         "0"
    _set_pref "browser.startup.page"                                "3"
    echo "  wrote: user.js (userChrome + dark mode + session restore)"
fi

# Save current theme name
echo "$THEME" > "$DOTFILES/.current-theme"

# Reload running apps (Linux only)
if [[ "$(uname -s)" == "Linux" ]]; then
    echo "==> Reloading..."

    if pgrep -x waybar > /dev/null 2>&1; then
        killall -SIGUSR2 waybar
        echo "  reloaded: waybar"
    fi

    if command -v hyprctl &> /dev/null && hyprctl monitors &> /dev/null; then
        hyprctl reload
        echo "  reloaded: hyprland"
    fi

    if pgrep -x ghostty > /dev/null 2>&1; then
        pkill -SIGUSR2 ghostty
        echo "  reloaded: ghostty"
    fi

    if pgrep -x firefox > /dev/null 2>&1; then
        pkill -x firefox
        sleep 1
        firefox &>/dev/null &
        echo "  restarted: firefox"
    fi

    if [[ -n "$WALLPAPER" ]] && pgrep -x awww-daemon > /dev/null 2>&1; then
        awww img "$DOTFILES/Wallpapers/$WALLPAPER" --transition-type center
        echo "  wallpaper: $WALLPAPER"
    fi
fi

echo "==> Done. Active theme: $THEME"
echo "    Restart nvim and run :Lazy sync to install any new colorscheme plugin."
