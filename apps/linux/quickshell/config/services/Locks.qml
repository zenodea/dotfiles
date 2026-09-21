pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool caps: false
    property bool num: false

    Process {
        running: true
        command: ["bash", `${Quickshell.shellDir}/scripts/locks.sh`]

        stdout: SplitParser {
            onRead: data => {
                const d = JSON.parse(data);
                root.caps = d.caps === 1;
                root.num = d.num === 1;
            }
        }
    }
}
