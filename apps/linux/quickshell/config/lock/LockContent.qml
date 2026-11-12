import QtQuick
import Quickshell
import qs.services
import qs.style
import qs.widgets

Column {
    spacing: 8

    Clock {
        anchors.horizontalCenter: parent.horizontalCenter
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Metrics.sectionSpacing * 2
        topPadding: 4

        Info {
            visible: Weather.known
            icon: Weather.icon
            text: `${Math.round(Weather.temp)}° ${Weather.label}`
        }

        Battery {}

        Info {
            visible: Media.player?.isPlaying ?? false
            icon: "󰎈"
            text: Media.player?.trackTitle ?? ""
        }
    }

    Item {
        width: 1
        height: 40
    }

    PasswordField {
        anchors.horizontalCenter: parent.horizontalCenter
    }

    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        height: 20
        text: Lock.checking ? "checking…" : Locks.caps ? "caps lock is on" : Lock.fails > 0 ? `wrong password · ${Lock.fails}` : ""
        color: Lock.checking ? Theme.muted : Locks.caps ? Theme.yellow : Theme.red
        font.pixelSize: 12
    }
}
