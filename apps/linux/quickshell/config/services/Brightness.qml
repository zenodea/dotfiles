pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    property string device: ""
    property int value: 0
    property int max: 0

    readonly property bool available: device !== "" && max > 0
    readonly property bool writable: Tools.has("brightnessctl")
    readonly property int percent: available ? Math.round(value / max * 100) : 0

    function set(pct: int): void {
        Quickshell.execDetached(["brightnessctl", "--device", device, "set", `${Math.max(1, Math.min(100, pct))}%`]);
    }

    Process {
        running: true
        command: ["sh", "-c", "ls -1 /sys/class/backlight 2>/dev/null | head -1"]

        stdout: StdioCollector {
            onStreamFinished: root.device = text.trim()
        }
    }

    FileView {
        path: root.device ? `/sys/class/backlight/${root.device}/brightness` : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.value = parseInt(text()) || 0
    }

    FileView {
        path: root.device ? `/sys/class/backlight/${root.device}/max_brightness` : ""
        onLoaded: root.max = parseInt(text()) || 0
    }
}
