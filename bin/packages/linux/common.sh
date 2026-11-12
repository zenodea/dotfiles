# common.sh — steps shared by the distro scripts. Arch only calls install_herdr,
# enable_services, configure_power_key, enroll_fingerprint and install_greeter;
# the rest covers what neither Fedora nor Debian packages.

has() { command -v "$1" &> /dev/null; }

# awww (wallpaper daemon) — only packaged on Arch, so build it with cargo.
install_awww() {
    has awww && return 0
    echo "==> Building awww from source..."
    has cargo || { echo "    cargo not found, skipping awww"; return 0; }
    cargo install --locked --git https://codeberg.org/LGFae/awww
}

# Nerd Font symbols — the waybar icons. No distro ships the symbols-only build.
install_nerd_symbols() {
    local dir="$HOME/.local/share/fonts/NerdFontsSymbolsOnly"
    [ -d "$dir" ] && return 0
    echo "==> Installing Nerd Font symbols..."
    mkdir -p "$dir"
    curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.tar.xz \
        | tar -xJ -C "$dir"
    fc-cache -f "$dir"
}

# Iosevka and Iosevka Aile — neither distro packages them.
install_iosevka() {
    local dir="$HOME/.local/share/fonts/Iosevka" tmp name
    [ -d "$dir" ] && return 0
    echo "==> Installing Iosevka..."
    mkdir -p "$dir"
    tmp="$(mktemp -d)"
    for name in Iosevka IosevkaAile; do
        curl -fsSL -o "$tmp/$name.zip" "$(curl -fsSL https://api.github.com/repos/be5invis/Iosevka/releases/latest \
            | grep -o "\"browser_download_url\": *\"[^\"]*/PkgTTC-$name-[0-9.]*\.zip\"" | cut -d'"' -f4)"
        unzip -oq "$tmp/$name.zip" -d "$dir"
    done
    rm -rf "$tmp"
    fc-cache -f "$dir"
}

install_commit_mono() {
    local dir="$HOME/.local/share/fonts/CommitMono" tmp
    [ -d "$dir" ] && return 0
    echo "==> Installing Commit Mono..."
    mkdir -p "$dir"
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/cm.zip" "$(curl -fsSL https://api.github.com/repos/eigilnikolajsen/commit-mono/releases/latest \
        | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | cut -d'"' -f4)"
    unzip -ojq "$tmp/cm.zip" '*.otf' -d "$dir"
    rm -rf "$tmp"
    fc-cache -f "$dir"
}

# Bibata cursors — hyprland.lua sets Bibata-Modern-Ice / Bibata-Modern-Classic.
install_bibata() {
    local dir="$HOME/.local/share/icons"
    [ -d "$dir/Bibata-Modern-Ice" ] && return 0
    echo "==> Installing Bibata cursors..."
    mkdir -p "$dir"
    for v in Ice Classic; do
        curl -fsSL "https://github.com/ful1e5/Bibata_Cursor/releases/latest/download/Bibata-Modern-$v.tar.xz" \
            | tar -xJ -C "$dir"
    done
}

install_oh_my_zsh() {
    [ -d "$HOME/.oh-my-zsh" ] && return 0
    echo "==> Installing oh-my-zsh..."
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}

# herdr — no distro packages it, so use its own installer (lands in ~/.local/bin).
install_herdr() {
    has herdr && return 0
    echo "==> Installing herdr..."
    curl -fsSL https://herdr.dev/install.sh | sh
}

install_zed() {
    has zed && return 0
    echo "==> Installing zed..."
    curl -fsSL https://zed.dev/install.sh | sh
}

# Desktop apps with no native package on either distro.
install_flatpaks() {
    has flatpak || { echo "    flatpak not found, skipping flatpaks"; return 0; }
    echo "==> Installing flatpaks..."
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak install -y --noninteractive flathub \
        md.obsidian.Obsidian \
        com.discordapp.Discord \
        com.spotify.Client
}

enable_services() {
    echo "==> Enabling services..."
    local unit
    for unit in bluetooth NetworkManager power-profiles-daemon upower mullvad-daemon; do
        systemctl list-unit-files "$unit.service" &> /dev/null \
            && sudo systemctl enable --now "$unit"
    done
    systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service \
        || echo "    no user session, skipping the audio units"
}

enroll_fingerprint() {
    has fprintd-list && [ -t 0 ] || return 0
    fprintd-list "$USER" 2> /dev/null | grep -q 'no fingers enrolled' || return 0
    local answer
    read -r -p "Fingerprint reader found with no fingers enrolled. Enroll one now? [y/N] " answer
    case "$answer" in y|Y|yes|YES) ;; *) return 0 ;; esac
    fprintd-enroll || echo "    enrollment failed, run fprintd-enroll later"
}

configure_power_key() {
    echo "==> Power key: press locks, hold 5s powers off..."
    sudo mkdir -p /etc/systemd/logind.conf.d
    printf '[Login]\nHandlePowerKey=lock\nHandlePowerKeyLongPress=poweroff\n' \
        | sudo tee /etc/systemd/logind.conf.d/power-key.conf > /dev/null
    sudo systemctl reload systemd-logind
}

install_greeter() {
    echo "==> Greeter: greetd running the Quickshell greeter..."
    local root src state first theme bg monitors published user home mono font
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
    src="$root/apps/linux/greetd"
    state="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/quickshell-theme.json"

    sudo install -d /etc/greetd
    sudo rm -rf /etc/greetd/quickshell
    sudo cp -rL "$root/apps/linux/quickshell/config" /etc/greetd/quickshell
    sudo install -m 644 "$src/config.toml" /etc/greetd/config.toml
    sudo install -m 644 "$src/pam" /etc/pam.d/greetd
    sudo install -m 755 "$src/password-only" /etc/greetd/password-only
    sudo install -m 755 "$src/fingerprint" /etc/greetd/fingerprint

    sudo install -d -m 1777 /var/lib/greeter-themes
    if [ -f "$state" ]; then
        cp "$state" "/var/lib/greeter-themes/$USER.json"
    fi

    first="$(awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)$/ { print $1; exit }' /etc/passwd)"
    theme="/var/lib/greeter-themes/$first.json"
    [ -f "$theme" ] || theme="$state"
    bg="$(jq -r '.colours.bg // empty' "$theme" 2> /dev/null | tr -d '#')"
    monitors="$(grep '^hl.monitor(' "$root/apps/linux/hypr/templates/hyprland.lua" 2> /dev/null || true)"
    {
        if [ -n "$monitors" ]; then printf '%s\n' "$monitors"; fi
        sed "s/@BG@/${bg:-282828}/" "$src/hyprland.lua"
    } | sudo tee /etc/greetd/hyprland.lua > /dev/null

    for published in /var/lib/greeter-themes/*.json; do
        [ -f "$published" ] || continue
        user="$(basename "$published" .json)"
        home="$(getent passwd "$user" | cut -d: -f6)"
        mono="$(jq -r '.font.mono // empty' "$published" 2> /dev/null)"
        [ -n "$home" ] && [ -n "$mono" ] || continue
        while read -r font; do
            sudo install -D -m 644 "$font" "/usr/local/share/fonts/greeter/$(basename "$font")"
        done < <(sudo -u "$user" env HOME="$home" fc-list "$mono" file | cut -d: -f1 | grep "^$home/")
    done
    if [ -d /usr/local/share/fonts/greeter ]; then
        sudo fc-cache -f /usr/local/share/fonts/greeter > /dev/null
    fi

    echo "    switch to it with: sudo systemctl enable --force greetd"
}
