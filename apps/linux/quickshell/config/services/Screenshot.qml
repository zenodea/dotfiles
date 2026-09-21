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
                cmd = `mkdir -p '${dir}' && grim -g "$(slurp)" "${file}"`;
            else if (mode === "clip")
                cmd = `grim -g "$(slurp)" - | wl-copy`;
            else if (mode === "clipScreen")
                cmd = "grim - | wl-copy";

            shot.toClipboard = mode === "clip" || mode === "clipScreen";
            shot.command = ["sh", "-c", cmd];
            shot.running = true;
        }
    }

    Process {
        id: shot

        property bool toClipboard: false

        onExited: code => {
            if (code !== 0)
                return;
            if (toClipboard)
                Notices.show("Screenshot", "Copied to clipboard", "󰆏");
            else
                Notices.show("Screenshot", "Saved to Pictures/Screenshots", "󰹑");
        }
    }
}
