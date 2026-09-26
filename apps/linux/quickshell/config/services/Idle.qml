pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool running: false
    property bool available: true

    readonly property bool inhibited: available && !running

    function toggle(): void {
        if (running)
            Quickshell.execDetached(["pkill", "-x", "hypridle"]);
        else
            Quickshell.execDetached(["hypridle"]);
        check.restart();
    }

    Process {
        id: probe

        command: ["sh", "-c", "command -v hypridle > /dev/null || exit 2; pgrep -x hypridle > /dev/null"]
        onExited: code => {
            root.available = code !== 2;
            root.running = code === 0;
        }
    }

    Timer {
        id: check

        running: true
        repeat: true
        interval: 5000
        triggeredOnStart: true
        onTriggered: probe.running = true
    }
}
