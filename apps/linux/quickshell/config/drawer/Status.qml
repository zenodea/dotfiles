pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import qs.popouts
import qs.services
import qs.style
import qs.widgets

Column {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    readonly property var battery: UPower.displayDevice
    readonly property real batteryRaw: battery?.percentage ?? 0
    readonly property int batteryPercent: Math.round(batteryRaw <= 1 ? batteryRaw * 100 : batteryRaw)
    readonly property bool charging: battery?.state === UPowerDeviceState.Charging || battery?.state === UPowerDeviceState.FullyCharged

    readonly property var netDevice: Networking.devices.values.find(d => d.connected) ?? null
    readonly property bool wifi: netDevice?.type === DeviceType.Wifi
    readonly property var network: netDevice?.networks?.values?.find(n => n.connected) ?? null

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property var btConnected: Bluetooth.devices.values.filter(d => d.connected)

    spacing: 10

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    Item {
        width: parent.width
        height: 20

        Text {
            id: volumeIcon

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.muted || root.volume === 0 ? "󰝟" : root.volume < 0.34 ? "󰕿" : root.volume < 0.67 ? "󰖀" : "󰕾"
            color: root.muted ? Theme.muted : Theme.fg
            font.family: Metrics.iconFont
            font.pixelSize: 16
            renderType: Text.NativeRendering

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                onClicked: {
                    if (root.sink?.audio)
                        root.sink.audio.muted = !root.sink.audio.muted;
                }
            }
        }

        Text {
            id: volumeValue

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            width: 34
            text: `${Math.round(root.volume * 100)}%`
            color: Theme.muted
            font.family: Theme.fontMono
            font.pixelSize: 10
            renderType: Text.NativeRendering
        }

        Slider {
            anchors.left: volumeIcon.right
            anchors.right: volumeValue.left
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            value: root.muted ? 0 : root.volume
            onMoved: v => {
                if (!root.sink?.audio)
                    return;
                root.sink.audio.muted = false;
                root.sink.audio.volume = v;
            }
        }
    }

    Item {
        width: parent.width
        height: 20
        visible: Brightness.available

        Text {
            id: brightnessIcon

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: Brightness.percent < 34 ? "󰃞" : Brightness.percent < 67 ? "󰃟" : "󰃠"
            color: Theme.fg
            font.family: Metrics.iconFont
            font.pixelSize: 16
            renderType: Text.NativeRendering
        }

        Text {
            id: brightnessValue

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            width: 34
            text: Brightness.writable ? `${Brightness.percent}%` : "×"
            color: Theme.muted
            font.family: Theme.fontMono
            font.pixelSize: 10
            renderType: Text.NativeRendering
        }

        Slider {
            anchors.left: brightnessIcon.right
            anchors.right: brightnessValue.left
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            value: Brightness.percent / 100
            fill: Theme.yellow
            enabled: Brightness.writable
            onMoved: v => Brightness.set(Math.round(v * 100))
        }
    }

    Row {
        id: chips

        width: parent.width
        spacing: 6

        readonly property int shown: (batteryChip.visible ? 1 : 0) + 1 + (bluetoothChip.visible ? 1 : 0)
        readonly property real cell: (width - spacing * (shown - 1)) / shown

        PillButton {
            id: batteryChip

            width: chips.cell
            maxTextWidth: chips.cell - 42
            icon: root.charging ? "󰂄" : "󰁹"
            label: `${root.batteryPercent}%`
            visible: root.battery?.isLaptopBattery ?? false
            enabled: false
        }

        PillButton {
            width: chips.cell
            maxTextWidth: chips.cell - 42
            icon: !root.netDevice ? "󰤭" : root.wifi ? "󰖩" : "󰈀"
            label: !root.netDevice ? "Offline" : root.wifi ? root.network?.name ?? "Wi-Fi" : "Ethernet"
            onClicked: Quickshell.execDetached(["ghostty", "-e", "nmtui"])
        }

        PillButton {
            id: bluetoothChip

            width: chips.cell
            maxTextWidth: chips.cell - 42
            icon: !(root.adapter?.enabled ?? false) ? "󰂲" : root.btConnected.length > 0 ? "󰂱" : "󰂯"
            label: root.btConnected.length > 0 ? root.btConnected[0].name : "Bluetooth"
            visible: !!root.adapter
            onClicked: Quickshell.execDetached(["blueman-manager"])
        }
    }

    Row {
        id: profiles

        width: parent.width
        spacing: 1

        readonly property var options: [
            {
                id: PowerProfile.PowerSaver,
                icon: "󰾆",
                label: "Saver"
            },
            {
                id: PowerProfile.Balanced,
                icon: "󰾅",
                label: "Balanced"
            },
            {
                id: PowerProfile.Performance,
                icon: "󰓅",
                label: "Performance"
            }
        ]

        readonly property int shown: PowerProfiles.hasPerformanceProfile ? 3 : 2

        Repeater {
            model: profiles.options

            Rectangle {
                id: segment

                required property var modelData

                readonly property bool active: PowerProfiles.profile === modelData.id

                visible: modelData.id !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile
                width: (profiles.width - (profiles.shown - 1)) / profiles.shown
                height: 30
                color: active ? Theme.alpha(Theme.accent, 0.22) : segmentArea.containsMouse ? Theme.alpha(Theme.fg, 0.09) : Theme.alpha(Theme.fg, 0.05)

                Behavior on color {
                    ColorAnimation {
                        duration: Metrics.shortAnim
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Metrics.gap

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: segment.modelData.icon
                        color: segment.active ? Theme.accent : Theme.muted
                        font.family: Metrics.iconFont
                        font.pixelSize: 13
                        renderType: Text.NativeRendering
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: segment.modelData.label
                        color: segment.active ? Theme.accent : Theme.fg
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                        renderType: Text.NativeRendering
                    }
                }

                MouseArea {
                    id: segmentArea

                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: PowerProfiles.profile = segment.modelData.id
                }
            }
        }
    }

    Row {
        width: parent.width
        spacing: 8
        visible: Shell.trayItems.length > 0

        Repeater {
            model: Shell.trayItems

            Item {
                id: entry

                required property SystemTrayItem modelData

                width: 22
                height: 22

                Image {
                    anchors.fill: parent
                    source: entry.modelData.icon
                    sourceSize.width: 44
                    sourceSize.height: 44
                    smooth: true
                }

                TrayMenu {
                    id: menu

                    trayItem: entry.modelData
                    anchorWindow: entry.QsWindow.window
                    anchorX: 0
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton && entry.modelData.hasMenu) {
                            menu.anchorX = entry.mapToItem(null, entry.width / 2, 0).x;
                            menu.open();
                            return;
                        }
                        if (mouse.button === Qt.RightButton) {
                            entry.modelData.secondaryActivate();
                            return;
                        }
                        entry.modelData.activate();
                        Panels.close();
                    }
                }
            }
        }
    }
}
