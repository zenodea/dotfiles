import QtQuick
import qs.style
import qs.widgets

Rectangle {
    id: root

    required property var item
    required property bool selected
    required property bool hovered

    function tone(kind: string): color {
        if (kind === "danger")
            return Theme.red;
        if (kind === "warn")
            return Theme.yellow;
        return Theme.fg;
    }

    color: selected ? Theme.alpha(Theme.accent, 0.16) : hovered ? Theme.alpha(Theme.fg, 0.1) : Theme.alpha(Theme.fg, 0.045)

    Behavior on color {
        ColorAnimation {
            duration: Metrics.shortAnim
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 7

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.item.icon ?? ""
            color: root.selected ? Theme.accent : root.tone(root.item.tone ?? "")
            font.pixelSize: 34

            Behavior on color {
                ColorAnimation {
                    duration: Metrics.shortAnim
                }
            }
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.item.name
            color: root.selected ? Theme.accent : Theme.fgBright
            font.pixelSize: 12
            font.bold: true
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.item.sub ?? ""
            color: Theme.muted
            font.pixelSize: 10
        }
    }
}
