pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.style
import qs.widgets

Column {
    id: root

    readonly property var cpu: Monitor.cpu
    readonly property var mem: Monitor.mem
    readonly property var power: Monitor.power
    readonly property real memTotal: Math.max(1, mem.total ?? 0)

    readonly property string layout: {
        const out = [];
        (cpu.cores ?? []).forEach((core, i) => {
            const last = out[out.length - 1];
            if (last && last.kind === core.kind)
                last.count++;
            else
                out.push({
                    kind: core.kind,
                    offset: i,
                    count: 1
                });
        });
        return JSON.stringify(out);
    }
    readonly property var groups: JSON.parse(layout)
    readonly property var titles: ({
            P: "Performance",
            E: "Efficient",
            LP: "Low power",
            C: "Cores"
        })

    function percent(value: real): string {
        return `${Math.round((value ?? 0) * 100)}%`;
    }

    function ifaceIcon(name: string): string {
        if (name.startsWith("wl"))
            return "󰖩";
        if (/^(tun|wg|tailscale|mullvad|proton|nordlynx)/.test(name))
            return "󰖂";
        return "󰈀";
    }

    spacing: 12

    component Caption: Label {
        color: Theme.muted
        font.pixelSize: 9
        font.letterSpacing: 1.2
    }

    component Heading: Item {
        id: heading

        property string title: ""
        property string value: ""

        width: parent.width
        height: headLeft.implicitHeight

        Label {
            id: headLeft

            width: parent.width - headRight.implicitWidth - 12
            elide: Text.ElideRight
            text: heading.title
            color: Theme.fgBright
            font.bold: true
        }

        Label {
            id: headRight

            anchors.right: parent.right
            text: heading.value
            color: Theme.fgBright
            font.bold: true
        }
    }

    component Meter: Item {
        id: meter

        property string label: ""
        property real value: 0
        property string text: ""
        property color tint: Theme.accent

        width: parent.width
        height: 18

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: meter.label
            color: Theme.muted
        }

        Rectangle {
            x: 72
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 72 - 52
            height: 6
            color: Theme.alpha(Theme.fg, 0.1)

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, meter.value))
                height: parent.height
                color: meter.tint

                Behavior on width {
                    Ease {}
                }
            }
        }

        Label {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: meter.text
            color: Theme.fgBright
        }
    }

    component CoreTile: Rectangle {
        id: tile

        property var core: ({})

        readonly property real usage: core.usage ?? 0
        readonly property color heat: usage >= 0.9 ? Theme.red : usage >= 0.6 ? Theme.orange : Theme.accent

        width: (parent.width - 18) / 4
        height: 44
        color: Theme.alpha(Theme.fg, 0.05)
        clip: true

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: parent.height * Math.max(0, Math.min(1, tile.usage))
            color: Theme.alpha(tile.heat, 0.3)

            Behavior on height {
                Ease {}
            }
        }

        Caption {
            x: 6
            y: 5
            text: tile.core.label ?? ""
        }

        Label {
            anchors.right: parent.right
            anchors.rightMargin: 6
            y: 3
            text: root.percent(tile.usage)
            color: Theme.fgBright
            font.bold: true
        }

        Label {
            x: 6
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            text: `${(tile.core.freq ?? 0).toFixed(1)}G`
            color: Theme.fg
            font.pixelSize: 9
        }

        Label {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            visible: tile.core.temp != null
            text: `${tile.core.temp}°`
            color: Monitor.heat(tile.core.temp ?? 0)
            font.pixelSize: 9
        }
    }

    component Tile: Rectangle {
        id: box

        property string icon: ""
        property color iconColour: Theme.fg
        property string caption: ""
        property string value: ""

        width: (parent.width - 6) / 2
        height: 44
        color: Theme.alpha(Theme.fg, 0.05)

        Icon {
            id: boxIcon

            x: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            text: box.icon
            color: box.iconColour
            font.pixelSize: 16
        }

        Column {
            anchors.left: boxIcon.right
            anchors.leftMargin: 6
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Caption {
                text: box.caption.toUpperCase()
            }

            Label {
                width: parent.width
                elide: Text.ElideRight
                text: box.value
                color: Theme.fgBright
            }
        }
    }

    component IoLine: Item {
        id: io

        property string icon: ""
        property string name: ""
        property string first: ""
        property string second: ""

        width: parent.width
        height: 22

        Icon {
            id: ioIcon

            anchors.verticalCenter: parent.verticalCenter
            width: 18
            text: io.icon
            color: Theme.accent
        }

        Label {
            anchors.left: ioIcon.right
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 18 - 4 - 168
            elide: Text.ElideRight
            text: io.name
            color: Theme.fgBright
        }

        Label {
            anchors.right: parent.right
            anchors.rightMargin: 84
            anchors.verticalCenter: parent.verticalCenter
            text: io.first
        }

        Label {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: io.second
            color: Theme.muted
        }
    }

    Card {
        width: parent.width
        title: "CPU"

        Heading {
            title: root.cpu.model ?? "CPU"
            value: root.percent(root.cpu.usage)
        }

        PopoutLabel {
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: 10
            text: [`${(root.cpu.freq ?? 0).toFixed(2)} GHz avg`, `load ${(root.cpu.load ?? []).map(v => v.toFixed(2)).join(" ")}`, root.cpu.temp ? `package ${root.cpu.temp}°` : ""].filter(Boolean).join("  ·  ")
        }

        PopoutLabel {
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: 10
            text: [`${Monitor.count} processes`, `${root.cpu.threads ?? 0} threads`, root.cpu.epp ? `EPP ${root.cpu.epp}` : root.cpu.governor ?? ""].filter(Boolean).join("  ·  ")
        }

        Repeater {
            model: root.groups

            Column {
                id: group

                required property var modelData

                width: parent.width
                topPadding: 4
                spacing: 6

                Caption {
                    text: `${root.titles[group.modelData.kind] ?? group.modelData.kind} · ${group.modelData.count}`.toUpperCase()
                }

                Grid {
                    width: parent.width
                    columns: 4
                    spacing: 6

                    Repeater {
                        model: group.modelData.count

                        CoreTile {
                            required property int index

                            core: root.cpu.cores?.[group.modelData.offset + index] ?? {}
                        }
                    }
                }
            }
        }
    }

    Repeater {
        model: Monitor.gpus.length

        Card {
            id: gpuCard

            required property int index

            readonly property var gpu: Monitor.gpus[index] ?? {}

            width: root.width
            title: "GPU"

            Heading {
                title: gpuCard.gpu.name ?? "GPU"
                value: !gpuCard.gpu.maxFreq ? "" : gpuCard.gpu.freq ? `${gpuCard.gpu.freq} / ${gpuCard.gpu.maxFreq} MHz` : "asleep"
            }

            Repeater {
                model: (gpuCard.gpu.engines ?? []).length

                Meter {
                    required property int index

                    readonly property var engine: gpuCard.gpu.engines?.[index] ?? {}

                    label: engine.name ?? ""
                    value: engine.busy ?? 0
                    text: root.percent(engine.busy)
                    tint: (engine.busy ?? 0) >= 0.9 ? Theme.red : Theme.purple
                }
            }

            PopoutLabel {
                width: parent.width
                wrapMode: Text.WordWrap
                font.pixelSize: 10
                text: [gpuCard.gpu.awake != null ? `awake ${root.percent(gpuCard.gpu.awake)}` : "", gpuCard.gpu.media != null ? `media ${root.percent(gpuCard.gpu.media)}` : "", gpuCard.gpu.mem ? `${Monitor.size(gpuCard.gpu.mem)} held by apps` : "", gpuCard.gpu.vramTotal ? `VRAM ${Monitor.size(gpuCard.gpu.vram)} / ${Monitor.size(gpuCard.gpu.vramTotal)}` : ""].filter(Boolean).join("  ·  ")
            }

            PopoutLabel {
                font.pixelSize: 10
                color: Theme.yellow
                text: (gpuCard.gpu.throttle ?? []).length > 0 ? `throttled: ${gpuCard.gpu.throttle.join(", ")}` : ""
            }

            ProcessList {
                width: parent.width
                topPadding: 4
                rows: Monitor.byGpu
                metric: "gpu"
                limit: 5
                empty: "No GPU clients"
            }
        }
    }

    Card {
        width: parent.width
        title: "Memory"

        Heading {
            title: `${Monitor.size(root.mem.used ?? 0)} used of ${Monitor.size(root.mem.total ?? 0)}`
            value: root.percent((root.mem.used ?? 0) / root.memTotal)
        }

        Row {
            id: stack

            width: parent.width
            height: 8

            Rectangle {
                width: stack.width * (root.mem.used ?? 0) / root.memTotal
                height: parent.height
                color: Theme.blue

                Behavior on width {
                    Ease {}
                }
            }

            Rectangle {
                width: stack.width * (root.mem.cache ?? 0) / root.memTotal
                height: parent.height
                color: Theme.alpha(Theme.blue, 0.35)

                Behavior on width {
                    Ease {}
                }
            }

            Rectangle {
                width: Math.max(0, stack.width - stack.children[0].width - stack.children[1].width)
                height: parent.height
                color: Theme.alpha(Theme.fg, 0.1)
            }
        }

        Row {
            spacing: 14

            Repeater {
                model: [
                    {
                        label: "used",
                        key: "used",
                        tint: Theme.blue
                    },
                    {
                        label: "cache",
                        key: "cache",
                        tint: Theme.alpha(Theme.blue, 0.35)
                    },
                    {
                        label: "free",
                        key: "free",
                        tint: Theme.alpha(Theme.fg, 0.2)
                    }
                ]

                Row {
                    id: swatch

                    required property var modelData

                    spacing: 5

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        color: swatch.modelData.tint
                    }

                    PopoutLabel {
                        font.pixelSize: 10
                        text: `${swatch.modelData.label} ${Monitor.size(root.mem[swatch.modelData.key] ?? 0)}`
                    }
                }
            }
        }

        PopoutLabel {
            font.pixelSize: 10
            text: (root.mem.swapTotal ?? 0) > 0 ? `swap ${Monitor.size(root.mem.swapUsed ?? 0)} / ${Monitor.size(root.mem.swapTotal)}${root.mem.zram ? " (zram)" : ""}` : "no swap"
        }

        ProcessList {
            width: parent.width
            topPadding: 4
            rows: Monitor.byMem
            metric: "mem"
            limit: 6
        }
    }

    Card {
        width: parent.width

        ProcessList {
            width: parent.width
            rows: Monitor.byCpu
            metric: "cpu"
            limit: 8
        }
    }

    Card {
        width: parent.width
        title: "Power & thermals"

        Grid {
            width: parent.width
            columns: 2
            spacing: 6

            Tile {
                visible: root.power.battery ?? false
                icon: "󱐋"
                iconColour: root.power.status === "Charging" ? Theme.green : (root.power.watts ?? 0) >= 25 ? Theme.orange : Theme.yellow
                caption: root.power.status === "Charging" ? "Charging" : root.power.ac ? "On AC" : "Draw"
                value: `${(root.power.watts ?? 0).toFixed(1)} W`
            }

            Tile {
                icon: "󰈐"
                iconColour: Monitor.fans.length > 0 ? Theme.accent : Theme.muted
                caption: "Fan"
                value: Monitor.fans.length > 0 ? Monitor.fans.map(rpm => `${rpm} rpm`).join(" · ") : "off"
            }
        }

        Grid {
            id: temps

            width: parent.width
            columns: 3
            spacing: 6

            Repeater {
                model: Monitor.temps.length

                Rectangle {
                    id: chip

                    required property int index

                    readonly property var sensor: Monitor.temps[index] ?? {}

                    width: (temps.width - 12) / 3
                    height: 34
                    color: Theme.alpha(Theme.fg, 0.05)

                    Caption {
                        x: 8
                        y: 4
                        width: parent.width - 16
                        elide: Text.ElideRight
                        text: (chip.sensor.name ?? "").toUpperCase()
                    }

                    Label {
                        x: 8
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        text: `${chip.sensor.value ?? 0}°`
                        color: Monitor.heat(chip.sensor.value ?? 0)
                        font.bold: true
                    }
                }
            }
        }
    }

    Card {
        width: parent.width
        title: "Disk & network"

        Repeater {
            model: Monitor.disks.length

            IoLine {
                required property int index

                readonly property var disk: Monitor.disks[index] ?? {}

                icon: "󰋊"
                name: disk.name ?? ""
                first: `R ${Monitor.rate(disk.read ?? 0)}`
                second: `W ${Monitor.rate(disk.write ?? 0)}`
            }
        }

        Repeater {
            model: (Monitor.net.ifaces ?? []).length

            IoLine {
                required property int index

                readonly property var iface: Monitor.net.ifaces?.[index] ?? {}

                icon: root.ifaceIcon(iface.name ?? "")
                name: iface.name ?? ""
                first: `↓ ${Monitor.rate(iface.rx ?? 0)}`
                second: `↑ ${Monitor.rate(iface.tx ?? 0)}`
            }
        }

        PopoutLabel {
            font.pixelSize: 10
            text: `/ ${root.percent(Monitor.disk)} full`
        }
    }
}
