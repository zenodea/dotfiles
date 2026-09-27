# shellcheck shell=bash
# dotfiles --doctor: dependency, symlink and drift checks; sourced by bin/dotfiles

OKS=0 WARNS=0 FAILS=0
C_OK="" C_WARN="" C_ERR="" C_OFF=""
if [ -t 1 ]; then
    C_OK=$'\033[32m' C_WARN=$'\033[33m' C_ERR=$'\033[31m' C_OFF=$'\033[0m'
fi

ok()   { echo "  ${C_OK}✓${C_OFF} $1"; OKS=$((OKS + 1)); }
warn() { echo "  ${C_WARN}!${C_OFF} $1"; WARNS=$((WARNS + 1)); }
bad()  { echo "  ${C_ERR}✗${C_OFF} $1"; FAILS=$((FAILS + 1)); }

check_dep() {
    if command -v "$1" > /dev/null 2>&1; then
        ok "$1"
    else
        warn "$1 not found${2:+ — $2}"
    fi
}

cmd_doctor() {
    echo "==> Platform: $PLATFORM"

    local theme
    theme="$(current_theme)"
    if [[ -n "$theme" && -f "$DOTFILES/themes/$theme.sh" ]]; then
        echo "==> Active theme: $theme"
    elif [[ -n "$theme" ]]; then
        echo "==> Active theme: $theme (theme file missing!)"
    else
        echo "==> Active theme: none (.current-theme not found)"
    fi

    local base
    if auto_enabled; then
        base="$(auto_base)"
        echo "==> Auto light/dark: on ($base ↔ $base-light, system says $(desired_appearance))"
    fi

    echo ""
    echo "==> Dependencies"
    check_dep git
    if command -v envsubst > /dev/null 2>&1; then
        ok "envsubst"
    else
        check_dep perl "needed as envsubst fallback"
    fi
    check_dep nvim
    if [[ "$PLATFORM" == "mac" ]]; then
        check_dep sketchybar
        check_dep borders
        check_dep fzf "used by dotfiles --pick"
    elif [[ "$PLATFORM" == "linux" ]]; then
        check_dep hyprctl
        check_dep waybar
        check_dep rofi
        check_dep fuzzel
        check_dep awww "needed for wallpapers"
        check_dep vifm
    fi

    echo ""
    echo "==> Symlinks"
    # install.sh --check walks the same map it links with, so the two can't drift
    # shellcheck source=/dev/null
    source "$DOTFILES/install.sh" --check

    echo ""
    echo "==> Config drift"
    local drift=$WARNS
    if [[ -z "$(ls -A "$WALLPAPERS_DIR" 2> /dev/null)" ]]; then
        warn "wallpapers submodule not checked out (run: dotfiles --sync)"
    fi
    # .auto-theme is tracked but the scheduler isn't, so a fresh clone can have
    # auto mode "on" with nothing actually driving it.
    if auto_enabled; then
        case "$PLATFORM" in
            mac)
                launchctl print "gui/$UID/$AGENT_LABEL" > /dev/null 2>&1 ||
                    warn "auto mode on but its launchd agent isn't loaded (dotfiles --auto on)"
                ;;
            linux)
                systemctl --user is-active dotfiles-appearance.timer > /dev/null 2>&1 ||
                    warn "auto mode on but its systemd timer isn't active (dotfiles --auto on)"
                ;;
        esac
    fi
    if ! git -C "$DOTFILES" diff --quiet || ! git -C "$DOTFILES" diff --cached --quiet; then
        warn "repo has uncommitted changes (dotfiles --save to commit & push)"
    fi
    if [[ $WARNS -eq $drift ]]; then
        echo "  none"
    fi

    echo ""
    echo "==> $OKS ok, $WARNS warnings, $FAILS problems"
    [[ $FAILS -eq 0 ]]
}
