pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import qs.services
import qs.style
import qs.widgets

Column {
    id: root

    readonly property date now: clock.date

    readonly property PwNode micSource: Pipewire.defaultAudioSource
    readonly property bool micMuted: micSource?.audio?.muted ?? false

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

    function screenshot(mode: string): void {
        Panels.close();
        shotDelay.mode = mode;
        shotDelay.restart();
    }

    spacing: 12

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSource]
    }

    Timer {
        id: shotDelay

        property string mode: "region"

        interval: 250
        onTriggered: {
            const dir = `${Quickshell.env("HOME")}/Pictures/Screenshots`;
            const file = `${dir}/$(date +%Y-%m-%d-%H%M%S).png`;
            let cmd = `mkdir -p '${dir}' && grim "${file}"`;
            if (mode === "region")
                cmd = `mkdir -p '${dir}' && grim -g "$(slurp)" "${file}"`;
            else if (mode === "clip")
                cmd = `grim -g "$(slurp)" - | wl-copy`;
            Quickshell.execDetached(["sh", "-c", cmd]);
        }
    }

    Row {
        width: parent.width
        spacing: 10

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: -4

            Text {
                text: Qt.formatDateTime(root.now, "HH:mm")
                color: Theme.fgBright
                font.family: Theme.fontMono
                font.pixelSize: 40
                font.bold: true
                renderType: Text.NativeRendering
            }

            Text {
                text: Qt.formatDateTime(root.now, "dddd, d MMMM")
                color: Theme.muted
                font.family: Theme.fontMono
                font.pixelSize: 11
                renderType: Text.NativeRendering
            }
        }
    }

    Card {
        width: parent.width
        title: Notifs.count > 0 ? `Notifications (${Notifs.count})` : "Notifications"

        Notifications {
            width: parent.width
        }
    }

    Card {
        width: parent.width
        title: "Status"

        Status {
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
    }

    Card {
        width: parent.width
        title: Qt.formatDateTime(root.now, "MMMM yyyy")

        Grid {
            columns: 7
            spacing: 0

            Repeater {
                model: ["S", "M", "T", "W", "T", "F", "S"]

                Item {
                    required property string modelData
                    required property int index

                    width: (root.width - 24) / 7
                    height: 18

                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: parent.index === 0 || parent.index === 6 ? Theme.alpha(Theme.accent, 0.8) : Theme.alpha(Theme.muted, 0.7)
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                        renderType: Text.NativeRendering
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

                    width: (root.width - 24) / 7
                    height: 26

                    Rectangle {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        color: cell.today ? Theme.accent : "transparent"
                        visible: cell.modelData > 0
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: cell.modelData > 0
                        text: cell.modelData
                        color: cell.today ? Theme.bg : cell.weekend ? Theme.muted : Theme.fg
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        font.bold: cell.today
                        renderType: Text.NativeRendering
                    }
                }
            }
        }
    }

    Rectangle {
        width: parent.width
        height: media.implicitHeight + 24
        color: Theme.surface
        visible: media.visible
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

    Card {
        width: parent.width
        title: "Quick actions"

        Toggle {
            width: parent.width
            icon: Networking.wifiEnabled ? "󰖩" : "󰖪"
            label: "Wi-Fi"
            checked: Networking.wifiEnabled
            onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
        }

        Toggle {
            width: parent.width
            visible: !!Bluetooth.defaultAdapter
            icon: (Bluetooth.defaultAdapter?.enabled ?? false) ? "󰂯" : "󰂲"
            label: "Bluetooth"
            checked: Bluetooth.defaultAdapter?.enabled ?? false
            onToggled: Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
        }

        Toggle {
            width: parent.width
            visible: !!root.micSource
            icon: root.micMuted ? "󰍭" : "󰍬"
            label: "Microphone"
            checked: !root.micMuted
            onToggled: {
                if (root.micSource?.audio)
                    root.micSource.audio.muted = !root.micSource.audio.muted;
            }
        }

        Toggle {
            width: parent.width
            enabled: Idle.available
            icon: Idle.inhibited ? "󰅶" : "󰾪"
            label: "Keep awake"
            checked: Idle.inhibited
            onToggled: Idle.toggle()
        }

        Toggle {
            width: parent.width
            visible: Vpn.state !== "absent"
            enabled: Vpn.state !== "down"
            icon: Vpn.connected ? "󰦝" : "󰦞"
            label: Vpn.state === "down" ? "Mullvad (daemon down)" : "Mullvad"
            checked: Vpn.connected
            onToggled: Vpn.toggle()
        }

        Toggle {
            width: parent.width
            enabled: Night.available
            icon: Night.on ? "󰖔" : "󰖙"
            label: "Night mode"
            checked: Night.on
            onToggled: Night.toggle()
        }
    }

    Card {
        width: parent.width
        title: "Capture"

        Grid {
            id: capture

            width: parent.width
            columns: 2
            spacing: 6

            readonly property real cell: (width - spacing) / 2

            PillButton {
                width: capture.cell
                maxTextWidth: capture.cell - 42
                icon: "󰹑"
                label: "Region"
                enabled: Tools.has("grim") && Tools.has("slurp")
                onClicked: root.screenshot("region")
            }

            PillButton {
                width: capture.cell
                maxTextWidth: capture.cell - 42
                icon: "󰆏"
                label: "Copy region"
                enabled: Tools.has("grim") && Tools.has("slurp") && Tools.has("wl-copy")
                onClicked: root.screenshot("clip")
            }

            PillButton {
                width: capture.cell
                maxTextWidth: capture.cell - 42
                icon: "󰍹"
                label: "Screen"
                enabled: Tools.has("grim")
                onClicked: root.screenshot("screen")
            }

            PillButton {
                width: capture.cell
                maxTextWidth: capture.cell - 42
                icon: Recorder.recording ? "󰙧" : "󰑊"
                label: Recorder.recording ? "Stop" : "Record screen"
                active: Recorder.recording
                enabled: Tools.has("wf-recorder")
                onClicked: Recorder.toggle(false)
            }

            PillButton {
                width: capture.cell
                maxTextWidth: capture.cell - 42
                icon: "󰻂"
                label: "Record region"
                visible: !Recorder.recording
                enabled: Tools.has("wf-recorder") && Tools.has("slurp")
                onClicked: Recorder.toggle(true)
            }
        }
    }
}
