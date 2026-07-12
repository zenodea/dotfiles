#!/usr/bin/env bash
# Shared setup for the Alfred workflow scripts.
#
# Alfred runs scripts with a bare environment, so the CLI's own dependencies
# (git, sketchybar, borders, envsubst) have to be put back on PATH by hand.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# The workflow folder is symlinked into Alfred's prefs, so resolving the script's
# physical location lands back in the repo even when the CLI isn't on PATH.
if command -v dotfiles > /dev/null 2>&1; then
    DF="$(command -v dotfiles)"
else
    # scripts → dotfiles → workflows → alfred → mac → apps → repo root
    _here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    DF="$(cd -P "$_here/../../../../../.." && pwd -P)/bin/dotfiles"
fi

if [ ! -x "$DF" ]; then
    echo "dotfiles CLI not found (run install.sh in the dotfiles repo)" >&2
    exit 1
fi
