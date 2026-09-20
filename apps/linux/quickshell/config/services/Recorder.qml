pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    property bool recording: false

    function stop(): void {
        Quickshell.execDetached(["pkill", "-INT", "-x", "wf-recorder"]);
        Notices.show("Recording", "Saved to Videos/Recordings", "󰑊");
        check.restart();
    }

    function start(region: bool): void {
        const dir = `${Quickshell.env("HOME")}/Videos/Recordings`;
        const geometry = region ? ` -g "$(slurp)"` : "";
        Quickshell.execDetached(["sh", "-c", `mkdir -p '${dir}' && wf-recorder${geometry} -f "${dir}/$(date +%Y-%m-%d-%H%M%S).mp4"`]);
        Notices.show("Recording", region ? "Pick a region" : "Started", "󰑊");
        check.restart();
    }

    function toggle(region: bool): void {
        if (recording)
            stop();
        else
            start(region);
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
