pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.services

Singleton {
    id: root

    readonly property string dir: `${Agent.workDir}/attachments`
    readonly property int maxBytes: 3500000
    readonly property var window: ToplevelManager.activeToplevel

    property var items: []

    signal added
    signal failed(string why)

    function add(item: var): void {
        items = items.concat([item]);
        added();
    }

    function remove(index: int): void {
        items = items.filter((item, i) => i !== index);
    }

    function take(): var {
        const out = items;
        items = [];
        return out;
    }

    function screen(): void {
        if (delay.running || shot.running)
            return;
        Panels.close();
        delay.restart();
    }

    function clipboard(): void {
        if (!paste.running)
            paste.running = true;
    }

    Timer {
        id: delay

        interval: 500
        onTriggered: {
            const window = root.window;
            const monitor = Hyprland.focusedMonitor?.name ?? "";
            shot.app = window?.appId ?? "";
            shot.note = "Attached: a screenshot of the user's screen" + (window ? `, where the focused window is ${window.appId} (${window.title}).` : ".");
            shot.command = ["sh", "-c", 'mkdir -p "$0" && find "$0" -type f -mtime +7 -delete; f="$0/$(date +%s%N).jpg"; timeout 5 grim ${1:+-o "$1"} -s 1 -t jpeg -q 85 "$f" && printf "%s\\n" "$f" && base64 -w0 "$f"', root.dir, monitor];
            shot.running = true;
        }
    }

    Process {
        id: shot

        property string app: ""
        property string note: ""

        stdout: StdioCollector {
            id: shotOut
        }

        onExited: code => {
            const lines = shotOut.text.split("\n");
            if (code === 0 && lines.length >= 2)
                root.add({
                    label: shot.app ? `screen · ${shot.app}` : "screen",
                    note: shot.note,
                    path: lines[0],
                    media: "image/jpeg",
                    data: lines[1]
                });
            else
                root.failed("screenshot failed");
            if (!Panels.controls)
                Panels.toggleControls("agent");
        }
    }

    Process {
        id: paste

        command: ["sh", "-c", 'type=$(wl-paste -l 2>/dev/null | grep -m1 -E "^image/(png|jpeg|webp|gif)$") || exit 2; mkdir -p "$0"; f="$0/$(date +%s%N).${type#image/}"; wl-paste -t "$type" > "$f" || exit 1; [ "$(stat -c%s "$f")" -le "$1" ] || { rm -f "$f"; exit 3; }; printf "%s\\n%s\\n" "$type" "$f"; base64 -w0 "$f"', root.dir, String(root.maxBytes)]

        stdout: StdioCollector {
            id: pasteOut
        }

        onExited: code => {
            const lines = pasteOut.text.split("\n");
            if (code === 0 && lines.length >= 3)
                root.add({
                    label: "clipboard image",
                    note: "Attached: an image from the user's clipboard.",
                    path: lines[1],
                    media: lines[0],
                    data: lines[2]
                });
            else if (code === 3)
                root.failed("clipboard image is too large");
        }
    }
}
