pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool recording: false

    function toggle(): void {
        if (recording) {
            Quickshell.execDetached(["pkill", "-INT", "-x", "wf-recorder"]);
        } else {
            const dir = `${Quickshell.env("HOME")}/Videos/Recordings`;
            Quickshell.execDetached(["sh", "-c", `mkdir -p '${dir}' && wf-recorder -f "${dir}/$(date +%Y-%m-%d-%H%M%S).mp4"`]);
        }
        check.restart();
    }

    Process {
        id: probe

        command: ["pgrep", "-x", "wf-recorder"]
        onExited: code => root.recording = code === 0
    }

    Timer {
        id: check

        running: true
        repeat: true
        interval: 3000
        triggeredOnStart: true
        onTriggered: probe.running = true
    }
}
