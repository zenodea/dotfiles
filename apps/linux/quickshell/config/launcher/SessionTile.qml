import QtQuick
import qs.style

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

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.item.icon ?? ""
            color: root.selected ? Theme.accent : root.tone(root.item.tone ?? "")
            font.family: Metrics.iconFont
            font.pixelSize: 34
            renderType: Text.NativeRendering

            Behavior on color {
                ColorAnimation {
                    duration: Metrics.shortAnim
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.item.name
            color: root.selected ? Theme.accent : Theme.fgBright
            font.family: Theme.fontMono
            font.pixelSize: 12
            font.bold: true
            renderType: Text.NativeRendering
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.item.sub ?? ""
            color: Theme.muted
            font.family: Theme.fontMono
            font.pixelSize: 10
            renderType: Text.NativeRendering
        }
    }
}
