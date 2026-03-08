#!/usr/bin/env bash
# install_packages.sh — install all packages needed for the Linux (Arch) setup
set -e

# ── Helpers ──────────────────────────────────────────────────────────────────

has() { command -v "$1" &>/dev/null; }

# ── Bootstrap yay (AUR helper) ───────────────────────────────────────────────

if ! has yay; then
    echo "==> Installing yay (AUR helper)..."
    sudo pacman -S --needed --noconfirm git base-devel
    tmp=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$tmp/yay"
    (cd "$tmp/yay" && makepkg -si --noconfirm)
    rm -rf "$tmp"
fi

# ── Pacman packages ───────────────────────────────────────────────────────────

PACMAN_PACKAGES=(
    # Hyprland stack
    hyprland
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk

    # Idle / lock / wallpaper
    hypridle
    hyprlock
    swww

    # Status bar
    waybar

    # Launchers
    fuzzel
    rofi-wayland

    # File managers
    vifm
    yazi

    # Terminal multiplexer
    tmux

    # Audio (Pipewire)
    pipewire
    pipewire-pulse
    wireplumber
    pavucontrol

    # Brightness
    brightnessctl

    # Screenshot / clipboard
    grim
    slurp
    wl-clipboard

    # Bluetooth
    bluez
    bluez-utils

    # Power profiles
    power-profiles-daemon

    # Browser
    firefox

    # Editors
    neovim

    # Git tooling
    git
    lazygit

    # Shell
    zsh

    # Fonts (Nerd Font symbols for waybar icons)
    ttf-nerd-fonts-symbols
    noto-fonts
    noto-fonts-emoji

    # Misc
    pyenv
    steam
    discord
)


echo "==> Installing pacman packages..."
sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}"

# ── AUR packages ─────────────────────────────────────────────────────────────

AUR_PACKAGES=(
    ghostty              # terminal
    zed                  # editor
    spotify-launcher     # spotify
    rofi-power-menu      # power menu plugin for rofi
    bibata-cursor-theme  # cursor theme
    oh-my-zsh-git        # zsh framework
)

echo "==> Installing AUR packages..."
yay -S --needed --noconfirm "${AUR_PACKAGES[@]}"

# ── Post-install ─────────────────────────────────────────────────────────────

echo "==> Enabling services..."
sudo systemctl enable --now bluetooth
sudo systemctl enable --now power-profiles-daemon

echo "Done. You may want to run create_symlinks.sh next to link your dotfiles."
