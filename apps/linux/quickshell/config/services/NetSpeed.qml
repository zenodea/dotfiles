pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string iface: ""
    property string rx: ""
    property string tx: ""
    property string down: ""
    property string up: ""

    readonly property bool connected: iface !== ""

    Process {
        running: true
        command: ["bash", `${Quickshell.shellDir}/scripts/net-speed.sh`]

        stdout: SplitParser {
            onRead: data => {
                const d = JSON.parse(data);
                root.iface = d.iface;
                root.rx = d.rx;
                root.tx = d.tx;
                root.down = d.down;
                root.up = d.up;
            }
        }
    }
}
