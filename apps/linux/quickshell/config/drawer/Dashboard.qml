pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.services
import qs.style
import qs.widgets

Column {
    id: root

    readonly property date now: clock.date

    spacing: 12

    onVisibleChanged: {
        if (visible)
            Updates.refresh();
    }

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    Item {
        width: parent.width
        height: clockFace.implicitHeight

        Column {
            id: clockFace

            spacing: -4

            Label {
                text: Qt.formatDateTime(root.now, "HH:mm")
                color: Theme.fgBright
                font.pixelSize: 40
                font.bold: true
            }

            Label {
                text: Qt.formatDateTime(root.now, "dddd, d MMMM")
                color: Theme.muted
            }
        }

        Column {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: Weather.known
            spacing: 2

            Row {
                anchors.right: parent.right
                spacing: 8

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Weather.icon
                    color: Theme.accent
                    font.pixelSize: 24
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: `${Math.round(Weather.temp)}°`
                    color: Theme.fgBright
                    font.pixelSize: 24
                    font.bold: true
                }
            }

            PopoutLabel {
                anchors.right: parent.right
                font.pixelSize: 10
                text: `${Weather.label}  ·  ${Math.round(Weather.low)}° – ${Math.round(Weather.high)}°`
            }
        }
    }

    Card {
        width: parent.width
        title: Notifs.count > 0 ? `Notifications (${Notifs.count})` : "Notifications"

        Toggle {
            width: parent.width
            icon: Notifs.dnd ? "󰂛" : "󰂚"
            label: "Do not disturb"
            checked: Notifs.dnd
            onToggled: Notifs.dnd = !Notifs.dnd
        }

        Notifications {
            width: parent.width
        }
    }

    Card {
        width: parent.width
        title: "System"

        Row {
            width: parent.width
            spacing: (parent.width - 4 * 74) / 3

            Gauge {
                value: SysInfo.cpu
                label: `${Math.round(SysInfo.cpu * 100)}%`
                caption: "CPU"
            }

            Gauge {
                value: SysInfo.mem
                label: `${(SysInfo.memUsedMb / 1024).toFixed(1)}G`
                caption: "RAM"
                fill: Theme.blue
            }

            Gauge {
                value: Math.min(1, SysInfo.temp / 100)
                label: `${SysInfo.temp}°`
                caption: "TEMP"
                fill: SysInfo.temp >= 80 ? Theme.red : SysInfo.temp >= 65 ? Theme.yellow : Theme.green
            }

            Gauge {
                value: SysInfo.disk
                label: `${Math.round(SysInfo.disk * 100)}%`
                caption: "DISK"
                fill: Theme.purple
            }
        }

        Status {
            width: parent.width
        }

        Item {
            width: parent.width
            height: upkeep.implicitHeight

            PopoutLabel {
                id: upkeep

                font.pixelSize: 10
                text: [`up ${SysInfo.uptimeText}`, Updates.summary].filter(Boolean).join("  ·  ")
            }

            PopoutLabel {
                anchors.right: parent.right
                font.pixelSize: 10
                color: Theme.yellow
                text: SysInfo.top ? `${SysInfo.top} ${SysInfo.topCpu}%` : ""
            }
        }
    }

    Card {
        width: parent.width
        title: Qt.formatDateTime(root.now, "MMMM yyyy")

        Calendar {
            width: parent.width
            now: root.now
        }
    }

    Rectangle {
        width: parent.width
        height: media.implicitHeight + 24
        color: Theme.surface
        visible: !!Media.player
        clip: true

        Image {
            anchors.fill: parent
            visible: media.art !== ""
            source: media.art
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            opacity: 0.25

            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1
                blurMax: 48
            }
        }

        MediaCard {
            id: media

            x: 12
            y: 12
            artSize: 56
            textWidth: root.width - 100
        }
    }
}
