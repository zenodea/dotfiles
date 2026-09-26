pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    function take(mode: string): void {
        Panels.close();
        delay.mode = mode;
        delay.restart();
    }

    Timer {
        id: delay

        property string mode: "region"

        interval: 250
        onTriggered: {
            const dir = `${Quickshell.env("HOME")}/Pictures/Screenshots`;
            const file = `${dir}/$(date +%Y-%m-%d-%H%M%S).png`;
            let cmd = `mkdir -p '${dir}' && grim "${file}"`;
            if (mode === "region")
                cmd = `mkdir -p '${dir}' && grim -g "$(slurp < /dev/null)" "${file}"`;
            else if (mode === "clip")
                cmd = `grim -g "$(slurp < /dev/null)" - | wl-copy`;
            else if (mode === "clipScreen")
                cmd = "grim - | wl-copy";

            shot.toClipboard = mode === "clip" || mode === "clipScreen";
            shot.running = false;
            shot.command = ["sh", "-c", cmd];
            shot.running = true;
        }
    }

    Process {
        id: shot

        property bool toClipboard: false

        stderr: StdioCollector {
            id: shotErr
        }

        onExited: code => {
            if (code !== 0) {
                const why = shotErr.text.trim().split("\n").pop();
                if (why && !why.includes("selection cancelled"))
                    Notices.show("Screenshot failed", why, "󰅙");
                return;
            }
            if (toClipboard)
                Notices.show("Screenshot", "Copied to clipboard", "󰆏");
            else
                Notices.show("Screenshot", "Saved to Pictures/Screenshots", "󰹑");
        }
    }
}
