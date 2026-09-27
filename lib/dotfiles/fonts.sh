# shellcheck shell=bash
# mono and text font switching; sourced by bin/dotfiles

cmd_font() {
    local arg="$1"

    if [[ -z "$arg" ]]; then
        local current name
        current="$(current_font)"
        echo "Available fonts:"
        while IFS= read -r name; do
            if [[ "$name" == "$current" ]]; then
                echo "  $name (active)"
            else
                echo "  $name"
            fi
        done < <(font_names)
        return 0
    fi

    if ! font_exists "$arg"; then
        echo "Error: font '$arg' not found (fonts/$arg.sh)" >&2
        echo "" >&2
        echo "Available fonts:" >&2
        font_names | sed 's/^/  /' >&2
        return 1
    fi

    echo "$arg" > "$DOTFILES/.current-font"

    local theme
    theme="$(current_theme)"
    if [[ -z "$theme" ]]; then
        echo "font: $arg (no active theme; applies on the next theme switch)"
        return 0
    fi
    exec "$DOTFILES/bin/switch-theme" "$theme"
}

cmd_text_font() {
    local arg="$1"

    if [[ -z "$arg" ]]; then
        local current name
        current="$(current_text_font)"
        echo "Available text fonts:"
        while IFS= read -r name; do
            if [[ "$name" == "$current" ]]; then
                echo "  $name (active)"
            else
                echo "  $name"
            fi
        done < <(text_font_names)
        return 0
    fi

    if ! text_font_exists "$arg"; then
        echo "Error: text font '$arg' not found (fonts/text/$arg.sh)" >&2
        echo "" >&2
        echo "Available text fonts:" >&2
        text_font_names | sed 's/^/  /' >&2
        return 1
    fi

    echo "$arg" > "$DOTFILES/.current-text-font"

    local theme
    theme="$(current_theme)"
    if [[ -z "$theme" ]]; then
        echo "text font: $arg (no active theme; applies on the next theme switch)"
        return 0
    fi
    exec "$DOTFILES/bin/switch-theme" "$theme"
}
