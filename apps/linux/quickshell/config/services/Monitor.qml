pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.style

Singleton {
    id: root

    readonly property bool open: Panels.drawer

    property bool ready: false
    property var cpu: ({})
    property var net: ({})
    property int count: 0
    property var byCpu: []
    property var byMem: []
    property var byGpu: []
    property var gpus: []
    property var temps: []
    property var fans: []
    property var mem: ({})
    property var power: ({})
    property var disks: []
    property int temp: 0
    property real disk: 0
    property int uptime: 0
    property var speed: ({
            iface: "",
            rx: [],
            tx: [],
            down: "",
            up: ""
        })

    readonly property bool online: speed.iface !== ""
    readonly property real memShare: (mem.used ?? 0) / Math.max(1, mem.total ?? 0)
    readonly property string uptimeText: {
        const d = Math.floor(uptime / 86400);
        const h = Math.floor(uptime % 86400 / 3600);
        const m = Math.floor(uptime % 3600 / 60);
        if (d > 0)
            return `${d}d ${h}h`;
        return h > 0 ? `${h}h ${m}m` : `${m}m`;
    }

    function rate(bytes: real): string {
        if (bytes >= 1048576)
            return `${(bytes / 1048576).toFixed(1)} MB/s`;
        if (bytes >= 1024)
            return `${Math.round(bytes / 1024)} KB/s`;
        return `${Math.round(bytes)} B/s`;
    }

    function size(bytes: real): string {
        if (bytes >= 1073741824)
            return `${(bytes / 1073741824).toFixed(1)}G`;
        if (bytes >= 1048576)
            return `${Math.round(bytes / 1048576)}M`;
        return bytes > 0 ? `${Math.round(bytes / 1024)}K` : "0";
    }

    function heat(celsius: int): color {
        return celsius >= 85 ? Theme.red : celsius >= 70 ? Theme.orange : celsius >= 55 ? Theme.yellow : Theme.green;
    }

    function load(data: string): void {
        let d;
        try {
            d = JSON.parse(data);
        } catch (e) {
            return;
        }
        if (d.speed) {
            root.speed = d.speed;
            return;
        }
        root.cpu = d.cpu;
        root.net = d.net;
        root.count = d.count;
        root.byCpu = d.byCpu;
        root.byMem = d.byMem;
        root.byGpu = d.byGpu;
        root.gpus = d.gpus;
        root.temps = d.temps;
        root.fans = d.fans;
        root.mem = d.mem;
        root.power = d.power;
        root.disks = d.disks;
        root.temp = d.temp;
        root.disk = d.disk;
        root.uptime = d.uptime;
        root.ready = true;
    }

    onOpenChanged: {
        if (proc.running)
            proc.write(open ? "open\n" : "closed\n");
    }

    Process {
        id: proc

        running: true
        stdinEnabled: true
        command: ["python3", `${Quickshell.shellDir}/scripts/monitor.py`, root.open ? "open" : "closed"]

        stdout: SplitParser {
            onRead: data => root.load(data)
        }

        onExited: revive.restart()
    }

    Timer {
        id: revive

        interval: 3000
        onTriggered: proc.running = true
    }
}
