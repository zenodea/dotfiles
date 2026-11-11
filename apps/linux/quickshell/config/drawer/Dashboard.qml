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
                value: Monitor.cpu.usage ?? 0
                label: `${Math.round((Monitor.cpu.usage ?? 0) * 100)}%`
                caption: "CPU"
            }

            Gauge {
                value: Monitor.memShare
                label: `${((Monitor.mem.used ?? 0) / 1073741824).toFixed(1)}G`
                caption: "RAM"
                fill: Theme.blue
            }

            Gauge {
                value: Math.min(1, Monitor.temp / 100)
                label: `${Monitor.temp}°`
                caption: "TEMP"
                fill: Monitor.temp >= 80 ? Theme.red : Monitor.temp >= 65 ? Theme.yellow : Theme.green
            }

            Gauge {
                value: Monitor.disk
                label: `${Math.round(Monitor.disk * 100)}%`
                caption: "DISK"
                fill: Theme.purple
            }
        }

        Status {
            width: parent.width
        }

        PopoutLabel {
            font.pixelSize: 10
            text: [`up ${Monitor.uptimeText}`, Updates.summary].filter(Boolean).join("  ·  ")
        }
    }

    Card {
        width: parent.width

        ProcessList {
            width: parent.width
            rows: Monitor.byCpu
            metric: "cpu"
            limit: 5
        }
    }

    Card {
        width: parent.width
        title: "Network"

        NetworkList {
            width: parent.width
            limit: 5
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
