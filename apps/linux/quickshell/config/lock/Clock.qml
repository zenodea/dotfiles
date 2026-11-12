import QtQuick
import Quickshell
import qs.style
import qs.widgets

Column {
    spacing: 8

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDateTime(clock.date, "HH:mm")
        color: Theme.fgBright
        font.pixelSize: 112
        font.bold: true
        renderType: Text.QtRendering
    }

    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
        color: Theme.muted
        font.pixelSize: 18
    }
}
