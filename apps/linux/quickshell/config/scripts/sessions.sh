#!/usr/bin/env bash

shopt -s nullglob
for f in /usr/share/wayland-sessions/*.desktop; do
    awk -v id="$(basename "$f" .desktop)" '
        /^\[/ { entry = ($0 == "[Desktop Entry]") }
        !entry { next }
        /^Name=/ && name == "" { name = substr($0, 6) }
        /^Exec=/ && exec == "" { exec = substr($0, 6) }
        /^DesktopNames=/ && desktops == "" { desktops = substr($0, 14) }
        /^(Hidden|NoDisplay)=true/ { hidden = 1 }
        END { if (name != "" && exec != "" && !hidden) printf "%s\t%s\t%s\t%s\n", id, name, exec, desktops }
    ' "$f"
done
