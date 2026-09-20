pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property real cpu: 0
    property real mem: 0
    property int memUsedMb: 0
    property int memTotalMb: 0
    property int temp: 0
    property real disk: 0

    Process {
        running: true
        command: ["bash", `${Quickshell.shellDir}/scripts/sysinfo.sh`]

        stdout: SplitParser {
            onRead: data => {
                const d = JSON.parse(data);
                root.cpu = d.cpu;
                root.mem = d.mem;
                root.memUsedMb = d.memUsedMb;
                root.memTotalMb = d.memTotalMb;
                root.temp = d.temp;
                root.disk = d.disk;
            }
        }
    }
}
