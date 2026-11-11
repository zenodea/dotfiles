pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.style
import qs.widgets

Column {
    id: root

    property int limit: 5

    readonly property var procs: Monitor.net?.procs ?? []
    readonly property var other: Monitor.net?.other ?? {
        rx: 0,
        tx: 0
    }
    readonly property real rx: Monitor.net?.rx ?? 0
    readonly property real tx: Monitor.net?.tx ?? 0
    readonly property real total: Math.max(1, rx + tx)
    readonly property bool leftover: other.rx + other.tx >= 1024
    readonly property real column: 72

    function speed(bytes: real): string {
        return bytes > 0 ? Monitor.rate(bytes) : "–";
    }

    spacing: 2

    Item {
        width: root.width
        height: summary.implicitHeight + 4

        Label {
            anchors.verticalCenter: summary.verticalCenter
            text: Monitor.net?.iface || "offline"
            color: Monitor.net?.iface ? Theme.accent : Theme.red
        }

        Label {
            id: summary

            anchors.right: parent.right
            text: `↓ ${Monitor.rate(root.rx)}   ↑ ${Monitor.rate(root.tx)}`
            color: Theme.fgBright
        }
    }

    Item {
        width: root.width
        height: 14

        Label {
            text: "PROCESS"
            color: Theme.muted
            font.pixelSize: 9
            font.letterSpacing: 1.2
        }

        Row {
            anchors.right: parent.right

            Repeater {
                model: ["DOWN", "UP"]

                Label {
                    required property string modelData

                    width: root.column
                    horizontalAlignment: Text.AlignRight
                    text: modelData
                    color: Theme.muted
                    font.pixelSize: 9
                    font.letterSpacing: 1.2
                }
            }
        }
    }

    Label {
        visible: root.procs.length === 0 && !root.leftover
        text: Monitor.ready ? "No traffic" : "Sampling…"
        color: Theme.muted
    }

    component Line: Item {
        id: line

        property string name: ""
        property real down: 0
        property real up: 0
        property bool dim: false

        width: root.width
        height: 24

        Label {
            y: 3
            width: parent.width - root.column * 2 - 8
            elide: Text.ElideRight
            text: line.name
            color: line.dim ? Theme.muted : Theme.fgBright
        }

        Row {
            anchors.right: parent.right
            y: 3

            Label {
                width: root.column
                horizontalAlignment: Text.AlignRight
                text: root.speed(line.down)
                color: line.dim ? Theme.muted : Theme.fg
            }

            Label {
                width: root.column
                horizontalAlignment: Text.AlignRight
                text: root.speed(line.up)
                color: Theme.muted
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            width: parent.width
            height: 2
            color: Theme.alpha(Theme.fg, 0.07)

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, (line.down + line.up) / root.total))
                height: parent.height
                color: line.dim ? Theme.alpha(Theme.muted, 0.6) : Theme.green

                Behavior on width {
                    Ease {}
                }
            }
        }
    }

    Repeater {
        model: Math.min(root.limit, root.procs.length)

        Line {
            required property int index

            readonly property var entry: root.procs[index] ?? {
                name: "",
                rx: 0,
                tx: 0
            }

            name: entry.name
            down: entry.rx
            up: entry.tx
            dim: entry.name === "system"
        }
    }

    Line {
        visible: root.leftover
        name: "other · UDP, VPN, root"
        down: root.other.rx
        up: root.other.tx
        dim: true
    }
}
