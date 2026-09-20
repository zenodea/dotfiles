pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property var presets: [60, 80, 90, 100]

    property bool supported: false
    property bool writable: false
    property string backend: "none"
    property int limit: 100
    property int pending: 100

    readonly property bool usable: supported && writable
    readonly property bool capped: supported && limit < 100

    function refresh(): void {
        if (!status.running)
            status.running = true;
    }

    function set(value: int): void {
        if (!usable || value === root.limit)
            return;
        root.pending = value;
        apply.command = ["bash", `${Quickshell.shellDir}/scripts/charge-limit.sh`, "set", String(value)];
        apply.running = true;
    }

    Process {
        id: status

        running: true
        command: ["bash", `${Quickshell.shellDir}/scripts/charge-limit.sh`, "status"]

        stdout: StdioCollector {
            onStreamFinished: {
                if (!text)
                    return;
                const state = JSON.parse(text);
                root.supported = state.supported;
                root.writable = state.writable;
                root.backend = state.backend;
                root.limit = state.limit;
            }
        }
    }

    Process {
        id: apply

        onExited: code => {
            if (code === 0)
                Notices.show("Charge limit", root.pending < 100 ? `Stopping at ${root.pending}%` : "Charging to full", "󰂄");
            settle.restart();
        }
    }

    Timer {
        id: settle

        interval: 250
        onTriggered: status.running = true
    }
}
