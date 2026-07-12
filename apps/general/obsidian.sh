# Obsidian — themes every vault listed in obsidian.json.
#
# Obsidian hot-reloads the active theme's CSS, so a restart is only needed when
# appearance.json (theme selection / accent) actually changes.

RESTART=0

obsidian_json() {
    local candidate
    for candidate in \
        "$HOME/Library/Application Support/obsidian/obsidian.json" \
        "$HOME/.config/obsidian/obsidian.json" \
        "$HOME/.var/app/md.obsidian.Obsidian/config/obsidian/obsidian.json"
    do
        if [[ -f "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

vaults() {
    python3 -c "
import json, sys
for v in json.load(open(sys.argv[1])).get('vaults', {}).values():
    print(v.get('path', ''))" "$1"
}

# Point the vault's appearance.json at our theme; prints "changed" if it moved.
select_theme() {
    python3 - "$1/.obsidian/appearance.json" "#$ACCENT" <<'PY'
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
}

render() {
    local config
    if ! config="$(obsidian_json)"; then
        skip "Obsidian not installed"
        return 0
    fi
    if ! have python3; then
        skip "python3 needed to read obsidian.json"
        return 0
    fi

    local vault
    while IFS= read -r vault; do
        [[ -n "$vault" && -d "$vault/.obsidian" ]] || continue
        generate obsidian/theme.css "$vault/.obsidian/themes/Dotfiles/theme.css"
        copy obsidian/manifest.json "$vault/.obsidian/themes/Dotfiles/manifest.json"
        [[ "$(select_theme "$vault")" == "changed" ]] && RESTART=1
    done < <(vaults "$config")

    return 0
}

reload_linux() {
    [[ "$RESTART" == 1 ]] && pgrep -x obsidian > /dev/null 2>&1 || return 0
    pkill -x obsidian
    sleep 1
    if have obsidian; then
        obsidian &> /dev/null &
        note "restarted"
    else
        note "quit — relaunch it to pick up the theme"
    fi
}

reload_mac() {
    [[ "$RESTART" == 1 ]] && pgrep -x Obsidian > /dev/null 2>&1 || return 0
    osascript -e 'tell application "Obsidian" to quit' > /dev/null 2>&1
    sleep 2
    open -a Obsidian
    note "restarted"
}
