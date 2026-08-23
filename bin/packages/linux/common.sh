# common.sh — steps shared by the Fedora and Debian scripts for things neither
# distro packages. Arch gets all of these from pacman/AUR and doesn't source this.

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
    sudo systemctl enable --now bluetooth
    sudo systemctl enable --now NetworkManager
    sudo systemctl enable --now power-profiles-daemon
    systemctl list-unit-files mullvad-daemon.service &> /dev/null \
        && sudo systemctl enable --now mullvad-daemon
}
