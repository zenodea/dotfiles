pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    readonly property int warm: 4000

    property int temperature: 0
    property bool available: true

    readonly property bool on: temperature === warm

    function toggle(): void {
        Quickshell.execDetached(["sh", "-c", `${Quickshell.env("HOME")}/scripts/night-mode`]);
        soon.restart();
    }

    Process {
        id: probe

        command: ["hyprctl", "hyprsunset", "temperature"]

        stdout: StdioCollector {
            onStreamFinished: {
                const value = parseInt(text.trim());
                root.available = !isNaN(value);
                root.temperature = root.available ? value : 0;
            }
        }
    }

    Timer {
        running: Panels.drawer
        interval: 2000
        repeat: true
        triggeredOnStart: true
        onTriggered: probe.running = true
    }

    Timer {
        id: soon

        interval: 500
        onTriggered: probe.running = true
    }
}
