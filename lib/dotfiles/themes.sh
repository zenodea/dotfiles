# shellcheck shell=bash
# picking a theme by hand, interactively or at random; sourced by bin/dotfiles

# Every theme that has both halves of a pair, listed by base name.
paired_themes() {
    local t
    while IFS= read -r t; do
        [[ "$t" == *-light ]] && continue
        if theme_paired "$t"; then echo "$t"; fi
    done < <(theme_names)
}

# A hand-picked theme should stick: rebase the pair if the pick has both halves,
# and pin now's appearance so the next tick waits for light/dark to actually flip.
apply_theme() {
    local theme="$1"
    if auto_enabled && theme_exists "$theme"; then
        if theme_paired "$theme"; then theme_base "$theme" > "$AUTO_FILE"; fi
        desired_appearance > "$PIN_FILE"
    fi
    exec "$DOTFILES/bin/switch-theme" "$theme"
}

cmd_pick() {
    local theme
    if command -v fzf > /dev/null 2>&1; then
        theme="$(theme_names | fzf \
            --prompt 'theme> ' \
            --height 40% --reverse \
            --preview "cat '$DOTFILES/themes/{}.sh'" \
            --preview-window right:50%)" || true
    else
        local names=()
        while IFS= read -r line; do names+=("$line"); done < <(theme_names)
        PS3="theme> "
        select theme in "${names[@]}"; do
            [[ -n "$theme" ]] && break
        done
    fi
    [[ -z "$theme" ]] && return 0
    apply_theme "$theme"
}

cmd_random() {
    local current names=()
    current="$(current_theme)"
    while IFS= read -r line; do
        [[ "$line" == "$current" ]] || names+=("$line")
    done < <(theme_names)
    if [[ ${#names[@]} -eq 0 ]]; then
        echo "Error: no other themes to pick from" >&2
        return 1
    fi
    apply_theme "${names[RANDOM % ${#names[@]}]}"
}
