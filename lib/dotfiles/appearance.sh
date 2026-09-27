# shellcheck shell=bash
# following the system light/dark setting, and its launchd/systemd scheduler; sourced by bin/dotfiles

AGENT_LABEL="com.zenodea.dotfiles-appearance"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
SYSTEMD_DIR="$HOME/.config/systemd/user"

# WatchPaths on .GlobalPreferences.plist is what makes this feel instant; it
# fires for unrelated prefs too, but a no-op tick is one `defaults read`.
# StartInterval backstops the writes cfprefsd coalesces, and ProcessType is left
# unset because "Background" let launchd stretch 60s out to several minutes.
scheduler_install_mac() {
    mkdir -p "$(dirname "$AGENT_PLIST")"
    cat > "$AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$DOTFILES/bin/dotfiles</string>
        <string>--sync-appearance</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>StartInterval</key><integer>60</integer>
    <key>WatchPaths</key>
    <array>
        <string>$HOME/Library/Preferences/.GlobalPreferences.plist</string>
    </array>
</dict>
</plist>
EOF
    launchctl bootout "gui/$UID/$AGENT_LABEL" > /dev/null 2>&1 || true
    launchctl bootstrap "gui/$UID" "$AGENT_PLIST" > /dev/null 2>&1 ||
        launchctl load "$AGENT_PLIST" > /dev/null 2>&1 || true
    echo "  scheduler: launchd agent $AGENT_LABEL (every 60s)"
}

scheduler_uninstall_mac() {
    launchctl bootout "gui/$UID/$AGENT_LABEL" > /dev/null 2>&1 ||
        launchctl unload "$AGENT_PLIST" > /dev/null 2>&1 || true
    rm -f "$AGENT_PLIST"
}

# Quarter-hourly rather than on the boundary, so a custom DOTFILES_DAY_START or
# a resume from suspend still lands; Persistent catches a boundary slept through.
scheduler_install_linux() {
    have systemctl || { echo "  scheduler: systemctl not found — skipped"; return 0; }
    mkdir -p "$SYSTEMD_DIR"
    cat > "$SYSTEMD_DIR/dotfiles-appearance.service" <<EOF
[Unit]
Description=Match the dotfiles theme to the time of day
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=$DOTFILES/bin/dotfiles --sync-appearance
EOF
    cat > "$SYSTEMD_DIR/dotfiles-appearance.timer" <<EOF
[Unit]
Description=Match the dotfiles theme to the time of day

[Timer]
OnCalendar=*-*-* *:00/15:00
OnBootSec=1min
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now dotfiles-appearance.timer > /dev/null 2>&1 || true
    echo "  scheduler: systemd timer dotfiles-appearance.timer (every 15m)"
}

scheduler_uninstall_linux() {
    have systemctl || return 0
    systemctl --user disable --now dotfiles-appearance.timer > /dev/null 2>&1 || true
    rm -f "$SYSTEMD_DIR/dotfiles-appearance."{service,timer}
    systemctl --user daemon-reload > /dev/null 2>&1 || true
}

scheduler_install()   { "scheduler_install_$PLATFORM"; }
scheduler_uninstall() { "scheduler_uninstall_$PLATFORM"; }

cmd_sync_appearance() {
    if ! auto_enabled; then
        if [ -t 1 ]; then echo "auto mode is off (dotfiles --auto on)"; fi
        return 0
    fi

    local want pin target
    want="$(desired_appearance)"
    pin="$(auto_pin)"

    # A hand-picked theme holds until the boundary moves out from under it.
    if [[ -n "$pin" ]]; then
        if [[ "$pin" == "$want" ]]; then return 0; fi
        rm -f "$PIN_FILE"
    fi

    target="$(theme_variant "$(auto_base)" "$want")"
    if ! theme_exists "$target"; then
        echo "Error: auto mode wants '$target', which doesn't exist" >&2
        return 1
    fi

    # This runs on a timer, so bail before a needless switch reloads sketchybar
    # and every terminal.
    if [[ "$(current_theme)" == "$target" ]]; then return 0; fi

    "$DOTFILES/bin/switch-theme" "$target"
}

cmd_auto() {
    local base pin
    case "${1:-status}" in
        on)
            # Already on means "put the scheduler back" (what install.sh wants),
            # so keep the tracked pair rather than rebasing onto the live theme.
            base="$(theme_base "$(auto_base)")"
            [[ -n "$base" ]] || base="$(theme_base "$(current_theme)")"
            if ! theme_paired "$base"; then
                echo "Error: '$base' has no light counterpart (themes/$base-light.sh)." >&2
                echo "" >&2
                echo "Paired themes:" >&2
                paired_themes | sed 's/^/  /' >&2
                return 1
            fi
            echo "$base" > "$AUTO_FILE"
            rm -f "$PIN_FILE"
            scheduler_install
            echo "auto: on — $base (dark) ↔ $base-light (light)"
            if [[ "$PLATFORM" == "mac" ]]; then
                echo "Set Appearance to Auto in System Settings to track sunrise/sunset."
            fi
            cmd_sync_appearance
            ;;
        off)
            rm -f "$AUTO_FILE" "$PIN_FILE"
            scheduler_uninstall
            echo "auto: off"
            ;;
        status)
            if ! auto_enabled; then
                echo "auto:    off"
                return 0
            fi
            base="$(auto_base)"
            pin="$(auto_pin)"
            echo "auto:    on"
            echo "pair:    $base (dark) ↔ $base-light (light)"
            echo "system:  $(desired_appearance)"
            echo "active:  $(current_theme)"
            if [[ -n "$pin" ]]; then
                echo "pinned:  manual pick, held until the system leaves $pin"
            fi
            ;;
        *)
            echo "Usage: dotfiles --auto [on|off|status]" >&2
            return 1
            ;;
    esac
}
