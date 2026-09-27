pragma ComponentBehavior: Bound

import QtQuick
import qs.style
import qs.widgets

Grid {
    id: root

    required property date now

    readonly property real cellWidth: width / 7

    readonly property var cells: {
        const year = now.getFullYear();
        const month = now.getMonth();
        const first = new Date(year, month, 1).getDay();
        const count = new Date(year, month + 1, 0).getDate();
        const out = [];
        for (let i = 0; i < first; i++)
            out.push(0);
        for (let d = 1; d <= count; d++)
            out.push(d);
        return out;
    }

    columns: 7

    Repeater {
        model: ["S", "M", "T", "W", "T", "F", "S"]

        Item {
            required property string modelData
            required property int index

            width: root.cellWidth
            height: 18

            Label {
                anchors.centerIn: parent
                text: parent.modelData
                color: parent.index === 0 || parent.index === 6 ? Theme.alpha(Theme.accent, 0.8) : Theme.alpha(Theme.muted, 0.7)
                font.pixelSize: 9
            }
        }
    }

    Repeater {
        model: root.cells

        Item {
            id: cell

            required property int modelData
            required property int index

            readonly property bool today: modelData === root.now.getDate()
            readonly property bool weekend: index % 7 === 0 || index % 7 === 6

            width: root.cellWidth
            height: 26

            Rectangle {
                anchors.centerIn: parent
                width: 24
                height: 24
                color: cell.today ? Theme.accent : "transparent"
                visible: cell.modelData > 0
            }

            Label {
                anchors.centerIn: parent
                visible: cell.modelData > 0
                text: cell.modelData
                color: cell.today ? Theme.bg : cell.weekend ? Theme.muted : Theme.fg
                font.bold: cell.today
            }
        }
    }
}
