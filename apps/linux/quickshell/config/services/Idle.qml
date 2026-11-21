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
        Quickshell.execDetached(running ? ["pkill", "-x", "hypridle"] : ["hypridle"]);
        running = !running;
        settle.restart();
    }

    Timer {
        id: settle

        interval: 600
        onTriggered: probe.running = true
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
