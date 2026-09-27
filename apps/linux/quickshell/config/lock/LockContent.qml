import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.services
import qs.style
import qs.widgets

Column {
    id: root

    readonly property var battery: UPower.displayDevice
    readonly property int percent: Math.round((battery?.percentage ?? 0) <= 1 ? (battery?.percentage ?? 0) * 100 : battery.percentage)
    readonly property bool charging: battery?.state === UPowerDeviceState.Charging || battery?.state === UPowerDeviceState.FullyCharged

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

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Metrics.sectionSpacing * 2
        topPadding: 4

        Info {
            visible: Weather.known
            icon: Weather.icon
            text: `${Math.round(Weather.temp)}° ${Weather.label}`
        }

        Info {
            visible: root.battery?.isLaptopBattery ?? false
            icon: root.charging ? "󰂄" : "󰁹"
            iconColor: root.charging ? Theme.green : root.percent <= 20 ? Theme.red : Theme.fg
            text: `${root.percent}%`
        }

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

    component Info: Row {
        property alias icon: glyph.text
        property alias iconColor: glyph.color
        property alias text: label.text

        spacing: Metrics.gap

        Icon {
            id: glyph

            anchors.verticalCenter: parent.verticalCenter
            color: Theme.accent
            font.pixelSize: Metrics.iconSize
        }

        Label {
            id: label

            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 260)
            elide: Text.ElideRight
            font.pixelSize: Metrics.fontSize
        }
    }
}
