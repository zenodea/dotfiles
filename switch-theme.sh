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

export THEME_NAME="$THEME"
export THEME_APPEARANCE="${APPEARANCE:-dark}"

# Derive <COLOR>_RGB ("r, g, b") for every palette color
for _c in BG SURFACE BG_ALT BORDER FG FG_BRIGHT ACCENT BLUE RED GREEN YELLOW ORANGE PURPLE; do
    eval "_hex=\$$_c"
    _r=$((16#${_hex:0:2})); _g=$((16#${_hex:2:2})); _b=$((16#${_hex:4:2}))
    eval "export ${_c}_RGB='$_r, $_g, $_b'"
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

# Only substitute theme variables, not any $variable references inside config files
VARS='${BG}${SURFACE}${BG_ALT}${BORDER}${FG}${FG_BRIGHT}${ACCENT}${BLUE}${RED}${GREEN}${YELLOW}${ORANGE}${PURPLE}${FG_RGB}${FG_BRIGHT_RGB}${BG_RGB}${SURFACE_RGB}${BG_ALT_RGB}${BORDER_RGB}${ACCENT_RGB}${BLUE_RGB}${RED_RGB}${GREEN_RGB}${YELLOW_RGB}${ORANGE_RGB}${PURPLE_RGB}${NVIM_PLUGIN}${NVIM_COLORSCHEME}${ZED_THEME}${GHOSTTY_THEME}${VIFM_COLORSCHEME}${THEME_NAME}${THEME_APPEARANCE}${ACCENT_H}${ACCENT_S}${ACCENT_L}'

# envsubst ships with gettext, which stock macOS lacks — fall back to perl
if command -v envsubst &> /dev/null; then
    substitute() { envsubst "$VARS"; }
else
    substitute() {
        THEME_VARS="$VARS" perl -pe \
            's/\$\{(\w+)\}/(index($ENV{THEME_VARS}, "{$1}") >= 0 && defined $ENV{$1}) ? $ENV{$1} : $&/ge'
    }
fi

generate() {
    local template="$1"
    local output="$2"
    mkdir -p "$(dirname "$output")"
    substitute < "$template" > "$output"
    echo "  wrote: ${output#"$DOTFILES"/}"
}

echo "==> Switching to: $THEME"

# Wallpaper — copied to a stable path so configs never embed machine paths
if [[ -n "$WALLPAPER" && -f "$DOTFILES/Wallpapers/$WALLPAPER" ]]; then
    cp "$DOTFILES/Wallpapers/$WALLPAPER" "$HOME/.config/current-wallpaper"
    echo "  wrote: ~/.config/current-wallpaper ($WALLPAPER)"
fi

# Hyprland
generate "$TEMPLATES_DIR/hypr/hyprland.conf"    "$DOTFILES/linux/config/hypr/hyprland.conf"
generate "$TEMPLATES_DIR/hypr/hyprlock.conf"    "$DOTFILES/linux/config/hypr/hyprlock.conf"

# Waybar
generate "$TEMPLATES_DIR/waybar/style.css"      "$DOTFILES/linux/config/waybar/style.css"

# Fuzzel
generate "$TEMPLATES_DIR/fuzzel/fuzzel.ini"     "$DOTFILES/linux/config/fuzzel/fuzzel.ini"

# Rofi
generate "$TEMPLATES_DIR/rofi/theme.rasi"       "$DOTFILES/linux/config/rofi/themes/current.rasi"

# macOS Sketchybar
generate "$TEMPLATES_DIR/sketchybar/colors.sh"  "$DOTFILES/mac/config/sketchybar/colors.sh"

# Neovim
generate "$TEMPLATES_DIR/nvim/colorscheme.lua"  "$DOTFILES/general/config/nvim/lua/plugins/colorscheme.lua"

# Zed
generate "$TEMPLATES_DIR/zed/settings.json"     "$DOTFILES/general/config/zed/settings.json"

# Ghostty — write directly to live config (not in dotfiles install)
generate "$TEMPLATES_DIR/ghostty/config"        "$HOME/.config/ghostty/config"

# vifm colorscheme include
generate "$TEMPLATES_DIR/vifm/theme.vifm"       "$DOTFILES/linux/config/vifm/theme.vifm"

# macOS borders
generate "$TEMPLATES_DIR/borders/bordersrc"     "$DOTFILES/mac/config/borders/bordersrc"

# macOS Sketchybar (rc file)
generate "$TEMPLATES_DIR/sketchybar/sketchybarrc" "$DOTFILES/mac/config/sketchybar/sketchybarrc"

# Raycast (imported via deeplink on macOS; JSON kept for Theme Studio import)
generate "$TEMPLATES_DIR/raycast/theme.json"      "$DOTFILES/mac/raycast/theme.json"

# Alfred (macOS) — theme goes straight into Alfred's preferences bundle,
# whose location is recorded in prefs.json (it may be a synced folder)
ALFRED_PREFS="" ALFRED_LOCALHASH=""
if [[ "$(uname -s)" == "Darwin" && -f "$HOME/Library/Application Support/Alfred/prefs.json" ]]; then
    IFS=$'\t' read -r ALFRED_PREFS ALFRED_LOCALHASH <<< "$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get('current', ''), d.get('localhash', ''), sep='\t')" \
        "$HOME/Library/Application Support/Alfred/prefs.json" 2>/dev/null)"
fi
if [[ -n "$ALFRED_PREFS" && -d "$ALFRED_PREFS" ]]; then
    # Custom themes live at the bundle root (like workflows/), NOT under
    # preferences/appearance/ — Alfred silently ignores themes placed there
    generate "$TEMPLATES_DIR/alfred/theme.json" \
        "$ALFRED_PREFS/themes/theme.custom.dotfiles.$THEME/theme.json"
fi

# Rofi power menu + theme picker
generate "$TEMPLATES_DIR/rofi/power-menu.rasi"   "$DOTFILES/linux/config/rofi/themes/power-menu.rasi"
generate "$TEMPLATES_DIR/rofi/theme-picker.rasi" "$DOTFILES/linux/config/rofi/themes/theme-picker.rasi"

# Firefox userChrome.css
FIREFOX_BASE=""
if [[ -f "$HOME/.mozilla/firefox/profiles.ini" ]]; then
    FIREFOX_BASE="$HOME/.mozilla/firefox"
elif [[ -f "$HOME/Library/Application Support/Firefox/profiles.ini" ]]; then
    FIREFOX_BASE="$HOME/Library/Application Support/Firefox"
fi
FIREFOX_PROFILE_DIR=""
if [[ -n "$FIREFOX_BASE" ]]; then
    _ff_rel=$(awk '/^\[Install/{found=1; next} found && /^Default=/{sub(/^Default=/, ""); print; exit}' \
        "$FIREFOX_BASE/profiles.ini" 2>/dev/null)
    if [[ -n "$_ff_rel" ]]; then
        FIREFOX_PROFILE_DIR="$FIREFOX_BASE/$_ff_rel"
    fi
fi
firefox_state() {
    cat "$FIREFOX_PROFILE_DIR/chrome/userChrome.css" \
        "$FIREFOX_PROFILE_DIR/chrome/userContent.css" \
        "$FIREFOX_PROFILE_DIR/user.js" 2>/dev/null | cksum
}

FIREFOX_CHANGED=0
if [[ -n "$FIREFOX_PROFILE_DIR" && -d "$FIREFOX_PROFILE_DIR" ]]; then
    _ff_before="$(firefox_state)"
    mkdir -p "$FIREFOX_PROFILE_DIR/chrome"
    generate "$TEMPLATES_DIR/firefox/userChrome.css"   "$FIREFOX_PROFILE_DIR/chrome/userChrome.css"
    generate "$TEMPLATES_DIR/firefox/userContent.css"  "$FIREFOX_PROFILE_DIR/chrome/userContent.css"
    # Ensure required prefs are set: userChrome.css + force dark mode
    _userjs="$FIREFOX_PROFILE_DIR/user.js"
    _set_pref() {
        local key="$1" val="$2"
        if grep -q "\"$key\"" "$_userjs" 2>/dev/null; then
            # -i.bak works with both GNU and BSD sed; bare -i doesn't
            sed -i.bak "s|user_pref(\"$key\",.*);|user_pref(\"$key\", $val);|" "$_userjs"
            rm -f "$_userjs.bak"
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
    if [[ "$(firefox_state)" != "$_ff_before" ]]; then
        FIREFOX_CHANGED=1
    fi
fi

# Obsidian — theme every vault listed in obsidian.json (both platforms).
# Obsidian hot-reloads the active theme's CSS; a restart is only needed
# when appearance.json (theme selection / accent) actually changes.
OBSIDIAN_RESTART=0
_obsidian_json=""
for _cand in "$HOME/Library/Application Support/obsidian/obsidian.json" \
             "$HOME/.config/obsidian/obsidian.json" \
             "$HOME/.var/app/md.obsidian.Obsidian/config/obsidian/obsidian.json"; do
    if [[ -f "$_cand" ]]; then
        _obsidian_json="$_cand"
        break
    fi
done
if [[ -n "$_obsidian_json" ]] && command -v python3 > /dev/null 2>&1; then
    while IFS= read -r _vault; do
        [[ -n "$_vault" && -d "$_vault/.obsidian" ]] || continue
        generate "$TEMPLATES_DIR/obsidian/theme.css" "$_vault/.obsidian/themes/Dotfiles/theme.css"
        cp "$TEMPLATES_DIR/obsidian/manifest.json"   "$_vault/.obsidian/themes/Dotfiles/manifest.json"
        _changed="$(python3 - "$_vault/.obsidian/appearance.json" "#$ACCENT" <<'PY'
import json, os, sys
path, accent = sys.argv[1], sys.argv[2]
d = {}
if os.path.exists(path):
    with open(path) as f:
        d = json.load(f)
before = (d.get("cssTheme"), d.get("theme"), d.get("accentColor"))
d["cssTheme"] = "Dotfiles"
d["theme"] = "obsidian"
d["accentColor"] = accent
with open(path, "w") as f:
    json.dump(d, f, indent=2)
print("changed" if before != ("Dotfiles", "obsidian", accent) else "unchanged")
PY
)"
        if [[ "$_changed" == "changed" ]]; then
            OBSIDIAN_RESTART=1
        fi
    done < <(python3 -c "
import json, sys
for v in json.load(open(sys.argv[1])).get('vaults', {}).values():
    print(v.get('path', ''))" "$_obsidian_json")
fi

# Save current theme name
echo "$THEME" > "$DOTFILES/.current-theme"

# Reload running apps
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

    if [[ "$FIREFOX_CHANGED" == 1 ]] && pgrep -x firefox > /dev/null 2>&1; then
        pkill -x firefox
        sleep 1
        firefox &>/dev/null &
        echo "  restarted: firefox"
    fi

    if [[ -n "$WALLPAPER" ]] && pgrep -x awww-daemon > /dev/null 2>&1; then
        awww img "$DOTFILES/Wallpapers/$WALLPAPER" --transition-type wipe --transition-duration 1 --transition-fps 60
        echo "  wallpaper: $WALLPAPER"
    fi

    if [[ "$OBSIDIAN_RESTART" == 1 ]] && pgrep -x obsidian > /dev/null 2>&1; then
        pkill -x obsidian
        sleep 1
        if command -v obsidian > /dev/null 2>&1; then
            obsidian &> /dev/null &
            echo "  restarted: obsidian"
        else
            echo "  obsidian: quit — relaunch it to pick up the theme"
        fi
    fi
elif [[ "$(uname -s)" == "Darwin" ]]; then
    echo "==> Reloading..."

    if pgrep -x sketchybar > /dev/null 2>&1; then
        sketchybar --reload
        echo "  reloaded: sketchybar"
    fi

    # Running borders with options updates the live instance
    if pgrep -x borders > /dev/null 2>&1; then
        bash "$DOTFILES/mac/config/borders/bordersrc"
        echo "  reloaded: borders"
    fi

    if [[ "$FIREFOX_CHANGED" == 1 ]] && pgrep -x firefox > /dev/null 2>&1; then
        pkill -x firefox
        sleep 1
        open -a Firefox
        echo "  restarted: firefox"
    fi

    # Use the source file: macOS caches by path, so re-setting the stable
    # copy's path with new content would be a no-op
    if [[ -n "$WALLPAPER" ]]; then
        if osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$DOTFILES/Wallpapers/$WALLPAPER\"" > /dev/null 2>&1; then
            echo "  wallpaper: $WALLPAPER"
        fi
    fi

    if [[ "$OBSIDIAN_RESTART" == 1 ]] && pgrep -x Obsidian > /dev/null 2>&1; then
        osascript -e 'tell application "Obsidian" to quit' > /dev/null 2>&1
        sleep 2
        open -a Obsidian
        echo "  restarted: obsidian"
    fi

    # Alfred — select the theme in the machine-local appearance prefs and
    # restart Alfred (background app, invisible). AppleScript "set theme"
    # silently no-ops when Alfred follows the macOS appearance.
    reload_alfred() {
        local plist="$ALFRED_PREFS/preferences/local/$ALFRED_LOCALHASH/appearance/prefs.plist"
        local uid="theme.custom.dotfiles.$THEME"
        mkdir -p "$(dirname "$plist")"
        [[ -f "$plist" ]] || plutil -create xml1 "$plist"
        plutil -replace theme         -string "$uid" "$plist"
        plutil -replace darkthemeuid  -string "$uid" "$plist"
        plutil -replace lightthemeuid -string "$uid" "$plist"
        # Hide the Alfred hat logo on the search window (synced appearance option)
        local options_plist="$ALFRED_PREFS/preferences/appearance/options/prefs.plist"
        mkdir -p "$(dirname "$options_plist")"
        [[ -f "$options_plist" ]] || plutil -create xml1 "$options_plist"
        plutil -replace hidehat -bool true "$options_plist"
        if pgrep -x Alfred > /dev/null 2>&1; then
            osascript -e 'tell application id "com.runningwithcrayons.Alfred" to quit' > /dev/null 2>&1
            sleep 1
            open -a "Alfred 5" 2>/dev/null || open -a Alfred
        fi
    }
    if [[ -n "$ALFRED_PREFS" && -n "$ALFRED_LOCALHASH" ]]; then
        if reload_alfred; then
            echo "  reloaded: alfred"
        else
            echo "  alfred: couldn't activate — pick 'Dotfiles $THEME' in Alfred's Appearance prefs"
        fi
    fi

    # Raycast — theme is imported via deeplink (Theme Studio needs one ⏎ to apply).
    # Color order per ray.so: bg, bgSecondary, text, selection, loader,
    # red, orange, yellow, green, blue, purple, magenta
    if [[ -d "/Applications/Raycast.app" || -d "$HOME/Applications/Raycast.app" ]]; then
        open "raycast://theme?version=1&name=${THEME}&appearance=${THEME_APPEARANCE}&colors=%23${BG},%23${SURFACE},%23${FG},%23${ACCENT},%23${ACCENT},%23${RED},%23${ORANGE},%23${YELLOW},%23${GREEN},%23${BLUE},%23${PURPLE},%23${PURPLE}"
        echo "  raycast: import opened — press ⏎ in Raycast to apply"
    fi
fi

echo "==> Done. Active theme: $THEME"
echo "    Restart nvim to pick up the new palette."
