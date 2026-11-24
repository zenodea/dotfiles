#!/usr/bin/env bash
# bootstrap.sh — set up a new machine in one go:
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/zenodea/dotfiles/main/bootstrap.sh)"
#
# 1. macOS: install Apple's command-line tools (git comes with them)
# 2. clone the repo with its wallpapers submodule, or pull if it's there
# 3. install packages (bin/install-packages picks Homebrew or the distro script)
# 4. link the configs and render the theme (install.sh)
# 5. make fish the login shell (its config hands interactive sessions to nu)
# 6. macOS: print the steps only you can do in System Settings
#
# Safe to rerun; every step skips what's already done. Override with:
#   DOTFILES_DIR   where the repo goes        (default ~/Github/dotfiles)
#   LOGIN_SHELL    shell to switch to, or ""  (default fish)
set -e

REPO="https://github.com/zenodea/dotfiles.git"
DIR="${DOTFILES_DIR:-$HOME/Github/dotfiles}"
LOGIN_SHELL="${LOGIN_SHELL-fish}"

has() { command -v "$1" &> /dev/null; }
step() { echo; echo "==> $1"; }

# ── 1. Command-line tools ────────────────────────────────────────────────────

if [ "$(uname -s)" = Darwin ] && ! xcode-select -p &> /dev/null; then
    step "Installing Apple's command-line tools (a dialog will open)..."
    xcode-select --install || true
    until xcode-select -p &> /dev/null; do sleep 5; done
fi

# ── 2. Repo ──────────────────────────────────────────────────────────────────

if [ -d "$DIR/.git" ]; then
    step "Updating $DIR..."
    git -C "$DIR" pull --ff-only
    git -C "$DIR" submodule update --init
else
    step "Cloning into $DIR..."
    mkdir -p "$(dirname "$DIR")"
    git clone --recurse-submodules "$REPO" "$DIR"
fi
cd "$DIR"

# ── 3. Packages ──────────────────────────────────────────────────────────────

step "Installing packages..."
bin/install-packages

# A fresh Homebrew isn't on this shell's PATH yet.
if ! has brew; then
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [ -x "$b" ] && eval "$("$b" shellenv)" && break
    done
fi

# ── 4. Configs and theme ─────────────────────────────────────────────────────

step "Linking configs and rendering the theme..."
./install.sh

# ── 5. Login shell ───────────────────────────────────────────────────────────

if [ -n "$LOGIN_SHELL" ] && shell_path="$(command -v "$LOGIN_SHELL")"; then
    if ! grep -qx "$shell_path" /etc/shells; then
        step "Adding $shell_path to /etc/shells (needs your password)..."
        echo "$shell_path" | sudo tee -a /etc/shells > /dev/null
    fi
    current="$(dscl . -read "/Users/$USER" UserShell 2> /dev/null | awk '{print $2}')"
    [ -n "$current" ] || current="$(getent passwd "$USER" 2> /dev/null | cut -d: -f7)"
    if [ "$current" != "$shell_path" ]; then
        step "Making $LOGIN_SHELL the login shell..."
        chsh -s "$shell_path"
    fi
elif [ -n "$LOGIN_SHELL" ]; then
    echo "    note: $LOGIN_SHELL isn't installed, login shell left as it is"
fi

# ── 6. What a script can't do ────────────────────────────────────────────────

if [ "$(uname -s)" = Darwin ]; then
    cat << EOF

==> Done. macOS needs a few things from you:

  1. Open AeroSpace, then allow it in System Settings → Privacy & Security →
     Accessibility, so it can move windows.
  2. Install Rex from its .dmg (it isn't on Homebrew), then turn on
     Settings → Rex Server → Remote Control, so theme switches reach it.
  3. Allow your terminal in System Settings → Privacy & Security →
     App Management, so the Zen live-theme loader can install. Then run:
     dotfiles --sync
  4. Open Tailscale and sign in.
  5. Open Raycast once, then load the dotfiles extension:
     cd "$DIR/apps/mac/raycast/extension" && npm run dev
     (Ctrl-C when it says "built extension successfully"; Raycast keeps it.)

  Log out and back in for the new login shell.
EOF
else
    echo
    echo "==> Done. Log out and back in for the new login shell."
fi
