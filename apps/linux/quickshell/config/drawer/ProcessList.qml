pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.style
import qs.widgets

Column {
    id: root

    property var rows: []
    property string metric: "cpu"
    property int limit: 5
    property string empty: "Nothing running"

    readonly property real memTotal: Math.max(1, Monitor.mem.total ?? 0)
    readonly property real column: 52
    readonly property var columns: metric === "gpu" ? ["GPU", "MEM"] : metric === "mem" ? ["MEM", "CPU"] : ["CPU", "MEM"]
    readonly property color tint: metric === "mem" ? Theme.blue : metric === "gpu" ? Theme.purple : Theme.accent

    function cell(row: var, title: string): string {
        if (title === "CPU")
            return `${row.cpu < 10 ? row.cpu.toFixed(1) : Math.round(row.cpu)}%`;
        if (title === "GPU")
            return `${Math.round(row.gpu * 100)}%`;
        return Monitor.size(metric === "gpu" ? row.gpuMem : row.mem);
    }

    function share(row: var): real {
        if (metric === "mem")
            return row.mem / memTotal;
        if (metric === "gpu")
            return row.gpu;
        return row.cpu / 100;
    }

    function hot(row: var): bool {
        return metric === "cpu" && row.cpu >= 90;
    }

    spacing: 2

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
                model: root.columns

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
        visible: root.rows.length === 0
        text: Monitor.ready ? root.empty : "Sampling…"
        color: Theme.muted
    }

    Repeater {
        model: Math.min(root.limit, root.rows.length)

        Item {
            id: row

            required property int index

            readonly property var entry: root.rows[index] ?? {
                name: "",
                count: 0,
                cpu: 0,
                mem: 0,
                gpu: 0,
                gpuMem: 0
            }

            width: root.width
            height: 24

            Row {
                id: who

                y: 3
                width: parent.width - root.column * root.columns.length - 8
                spacing: 4

                Label {
                    id: name

                    width: Math.min(implicitWidth, who.width - (times.visible ? times.implicitWidth + who.spacing : 0))
                    elide: Text.ElideRight
                    text: row.entry.name
                    color: root.hot(row.entry) ? Theme.red : Theme.fgBright
                }

                Label {
                    id: times

                    anchors.baseline: name.baseline
                    visible: row.entry.count > 1
                    text: `×${row.entry.count}`
                    color: Theme.muted
                    font.pixelSize: 9
                }
            }

            Row {
                anchors.right: parent.right
                y: 3

                Repeater {
                    model: root.columns

                    Label {
                        required property string modelData
                        required property int index

                        width: root.column
                        horizontalAlignment: Text.AlignRight
                        text: root.cell(row.entry, modelData)
                        color: index > 0 ? Theme.muted : root.hot(row.entry) ? Theme.red : Theme.fg
                    }
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                width: parent.width
                height: 2
                color: Theme.alpha(Theme.fg, 0.07)

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, root.share(row.entry)))
                    height: parent.height
                    color: root.hot(row.entry) ? Theme.red : root.tint

                    Behavior on width {
                        Ease {}
                    }
                }
            }
        }
    }
}
