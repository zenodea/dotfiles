#!/usr/bin/env bash
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

for directory in "$here/../config/"*/; do
    ln -s -- "$directory" "$fixture/$(basename -- "$directory")"
done
cp -- "$here/shell.qml" "$fixture/shell.qml"

# Isolate the persistent mode marker and compositor connection from the live session.
mkdir -m 700 "$fixture/runtime"
export QT_QPA_PLATFORM=offscreen
export XDG_RUNTIME_DIR="$fixture/runtime"
export HYPRLAND_INSTANCE_SIGNATURE=quickshell-tests-no-compositor

run_test() {
    timeout 15s qs -p "$fixture" --no-color >"$fixture/output" 2>&1 || {
        grep -E 'FAIL:|ERROR|WARN|PASS:' "$fixture/output" || true
        exit 1
    }
    grep -F "$1" "$fixture/output"
    ! grep -Eq 'FAIL:|ERROR|TypeError|ReferenceError' "$fixture/output"
}

run_test 'PASS: Wi-Fi password entry, retries, and sticky Zen mode'
TEST_ZEN_RESTORE=1 run_test 'PASS: Zen mode persists across shell restarts'

# The palette test reads the real audio server but writes its state under the fixture.
cp -- "$here/palette.qml" "$fixture/shell.qml"
mkdir -p "$fixture/state/dotfiles"
XDG_STATE_HOME="$fixture/state" PIPEWIRE_RUNTIME_DIR="/run/user/$(id -u)" run_test 'PASS: palette search, scopes, toggles, pins, and command output'
