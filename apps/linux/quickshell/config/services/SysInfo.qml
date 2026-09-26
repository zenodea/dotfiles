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
    property int uptime: 0
    property string top: ""
    property int topCpu: 0

    readonly property string uptimeText: {
        const d = Math.floor(uptime / 86400);
        const h = Math.floor(uptime % 86400 / 3600);
        const m = Math.floor(uptime % 3600 / 60);
        if (d > 0)
            return `${d}d ${h}h`;
        return h > 0 ? `${h}h ${m}m` : `${m}m`;
    }

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
                root.uptime = d.uptime ?? 0;
                root.top = d.top ?? "";
                root.topCpu = d.topCpu ?? 0;
            }
        }
    }
}
