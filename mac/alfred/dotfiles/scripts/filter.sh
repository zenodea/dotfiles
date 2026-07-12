#!/usr/bin/env bash
# Alfred Script Filter — builds the menu for the `dotfiles` keyword.
#
# Emits Alfred JSON. Matching is done here rather than by Alfred, because the
# query carries a subcommand prefix ("theme nord") that Alfred would otherwise
# try to match against the item titles.
set -uo pipefail
source "$(dirname "$0")/common.sh"

query="${1:-}"

json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# Case-insensitive substring match; an empty needle matches everything.
matches() {
    local needle="$2"
    [ -z "$needle" ] && return 0
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        *"$(printf '%s' "$needle" | tr '[:upper:]' '[:lower:]')"*) return 0 ;;
        *) return 1 ;;
    esac
}

ITEMS=""

# cmd, value, output_style ride along as Alfred variables so the action script
# never has to re-parse a command line (wallpaper names may contain spaces).
add_item() {
    local title="$1" subtitle="$2" cmd="$3" value="${4:-}" style="${5:-notification}"
    [ -n "$ITEMS" ] && ITEMS="$ITEMS,"
    ITEMS="$ITEMS
  {
    \"uid\": \"$(json_escape "$cmd $value")\",
    \"title\": \"$(json_escape "$title")\",
    \"subtitle\": \"$(json_escape "$subtitle")\",
    \"arg\": \"$(json_escape "$title")\",
    \"variables\": {
      \"cmd\": \"$(json_escape "$cmd")\",
      \"value\": \"$(json_escape "$value")\",
      \"output_style\": \"$style\"
    }
  }"
}

# A drill-down row: not actionable, Tab completes it into the query.
add_prefix() {
    local title="$1" subtitle="$2" autocomplete="$3"
    [ -n "$ITEMS" ] && ITEMS="$ITEMS,"
    ITEMS="$ITEMS
  {
    \"uid\": \"$(json_escape "$title")\",
    \"title\": \"$(json_escape "$title")\",
    \"subtitle\": \"$(json_escape "$subtitle")\",
    \"valid\": false,
    \"autocomplete\": \"$(json_escape "$autocomplete")\"
  }"
}

add_message() {
    ITEMS="
  {
    \"title\": \"$(json_escape "$1")\",
    \"subtitle\": \"$(json_escape "${2:-}")\",
    \"valid\": false
  }"
}

current="$("$DF" --current 2>/dev/null)"

case "$query" in
    theme\ *|theme)
        needle="${query#theme}"
        needle="${needle# }"
        while IFS= read -r name; do
            [ -n "$name" ] || continue
            matches "$name" "$needle" || continue
            if [ "$name" = "$current" ]; then
                add_item "$name" "Active theme — re-apply" "--theme" "$name"
            else
                add_item "$name" "Switch to $name" "--theme" "$name"
            fi
        done < <("$DF" --themes-plain 2>/dev/null)
        [ -z "$ITEMS" ] && add_message "No theme matches “${needle}”"
        ;;

    wallpaper\ *|wallpaper)
        needle="${query#wallpaper}"
        needle="${needle# }"
        matches "random" "$needle" &&
            add_item "random" "Set a random wallpaper" "--wallpaper" "random"
        while IFS= read -r name; do
            [ -n "$name" ] || continue
            matches "$name" "$needle" || continue
            add_item "$name" "Set wallpaper (theme switch will reset it)" "--wallpaper" "$name"
        done < <("$DF" --wallpapers-plain 2>/dev/null)
        [ -z "$ITEMS" ] && add_message "No wallpaper matches “${needle}”"
        ;;

    *)
        matches "theme" "$query" &&
            add_prefix "theme" "Switch theme${current:+ — currently $current}" "theme "
        matches "wallpaper" "$query" &&
            add_prefix "wallpaper" "Set the wallpaper only" "wallpaper "
        matches "random" "$query" &&
            add_item "random" "Switch to a random theme" "--random"
        matches "update" "$query" &&
            add_item "update" "git pull, then re-apply the current theme" "--update" "" "largetype"
        matches "sync" "$query" &&
            add_item "sync" "Re-run install.sh (re-link configs)" "--sync" "" "largetype"
        matches "doctor" "$query" &&
            add_item "doctor" "Check symlinks, dependencies, and config drift" "--doctor" "" "largetype"
        matches "save" "$query" &&
            add_item "save" "git add + commit + push the dotfiles repo" "--save"
        [ -z "$ITEMS" ] && add_message "No command matches “${query}”" "Try: theme, wallpaper, random, update, sync, doctor, save"
        ;;
esac

printf '{"items": [%s\n]}\n' "$ITEMS"
