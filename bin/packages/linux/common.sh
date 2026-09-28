# common.sh — steps shared by the distro scripts. Arch only calls install_herdr and
# enable_services; the rest covers what neither Fedora nor Debian packages.

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

# Bibata cursors — hyprland.conf sets Bibata-Modern-Ice / Bibata-Modern-Classic.
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
