import QtQuick
import qs.style
import qs.widgets

Rectangle {
    id: root

    required property string text
    required property string detail
    required property string phase

    width: ListView.view.width
    implicitHeight: 32
    color: Theme.alpha(Theme.fg, 0.05)

    Row {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: Metrics.gap

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            text: root.phase === "running" ? "󰔟" : root.phase === "error" ? "󰅖" : "󰄬"
            color: root.phase === "running" ? Theme.yellow : root.phase === "error" ? Theme.red : Theme.green
        }

        Label {
            id: toolName

            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: Theme.accent
            font.pixelSize: 13
        }

        Label {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - toolName.width - 40
            elide: Text.ElideRight
            text: root.detail
            color: Theme.muted
            font.pixelSize: 13
        }
    }
}
