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

    function screenshot(region: bool): void {
        Panels.close();
        shotDelay.region = region;
        shotDelay.restart();
    }

    spacing: 12

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    Timer {
        id: shotDelay

        property bool region: false

        interval: 250
        onTriggered: {
            const dir = `${Quickshell.env("HOME")}/Pictures/Screenshots`;
            const file = `${dir}/$(date +%Y-%m-%d-%H%M%S).png`;
            const cmd = region ? `mkdir -p '${dir}' && grim -g "$(slurp)" "${file}"` : `mkdir -p '${dir}' && grim "${file}"`;
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
                text: Qt.formatDateTime(root.now, "hh:mm")
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

        Item {
            width: parent.width - 180
            height: 1
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(root.now, "AP")
            color: Theme.alpha(Theme.muted, 0.6)
            font.family: Theme.fontMono
            font.pixelSize: 11
            renderType: Text.NativeRendering
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

        Flow {
            width: parent.width
            spacing: 6

            PillButton {
                icon: Idle.inhibited ? "󰅶" : "󰾪"
                label: Idle.inhibited ? "Awake" : "Idle"
                active: Idle.inhibited
                enabled: Idle.available
                onClicked: Idle.toggle()
            }

            PillButton {
                icon: "󰖔"
                label: "Night"
                onClicked: Quickshell.execDetached(["sh", "-c", `${Quickshell.env("HOME")}/scripts/night-mode`])
            }

            PillButton {
                icon: "󰹑"
                label: "Region"
                enabled: Tools.has("grim") && Tools.has("slurp")
                onClicked: root.screenshot(true)
            }

            PillButton {
                icon: "󰍹"
                label: "Screen"
                enabled: Tools.has("grim")
                onClicked: root.screenshot(false)
            }

            PillButton {
                icon: Recorder.recording ? "󰙧" : "󰑊"
                label: Recorder.recording ? "Stop" : "Record"
                active: Recorder.recording
                enabled: Tools.has("wf-recorder")
                onClicked: Recorder.toggle()
            }
        }
    }
}
