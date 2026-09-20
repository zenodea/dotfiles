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

    Row {
        width: parent.width
        spacing: 10

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.muted || root.volume === 0 ? "󰝟" : root.volume < 0.34 ? "󰕿" : root.volume < 0.67 ? "󰖀" : "󰕾"
            color: root.muted ? Theme.muted : Theme.fg
            font.family: Metrics.iconFont
            font.pixelSize: 16
            renderType: Text.NativeRendering

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (root.sink?.audio)
                        root.sink.audio.muted = !root.sink.audio.muted;
                }
            }
        }

        Slider {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 86
            value: root.muted ? 0 : root.volume
            onMoved: v => {
                if (!root.sink?.audio)
                    return;
                root.sink.audio.muted = false;
                root.sink.audio.volume = v;
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: `${Math.round(root.volume * 100)}%`
            color: Theme.muted
            font.family: Theme.fontMono
            font.pixelSize: 10
            renderType: Text.NativeRendering
        }
    }

    Row {
        width: parent.width
        spacing: 10
        visible: Brightness.available

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Brightness.percent < 34 ? "󰃞" : Brightness.percent < 67 ? "󰃟" : "󰃠"
            color: Theme.fg
            font.family: Metrics.iconFont
            font.pixelSize: 16
            renderType: Text.NativeRendering
        }

        Slider {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 86
            value: Brightness.percent / 100
            fill: Theme.yellow
            onMoved: v => Brightness.set(Math.round(v * 100))
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: `${Brightness.percent}%`
            color: Theme.muted
            font.family: Theme.fontMono
            font.pixelSize: 10
            renderType: Text.NativeRendering
        }
    }

    Flow {
        width: parent.width
        spacing: 6

        PillButton {
            icon: root.charging ? "󰂄" : "󰁹"
            label: `${root.batteryPercent}%`
            visible: root.battery?.isLaptopBattery ?? false
            enabled: false
        }

        PillButton {
            icon: !root.netDevice ? "󰤭" : root.wifi ? "󰖩" : "󰈀"
            label: !root.netDevice ? "Offline" : root.wifi ? root.network?.name ?? "Wi-Fi" : "Ethernet"
            onClicked: Quickshell.execDetached(["ghostty", "-e", "nmtui"])
        }

        PillButton {
            icon: !(root.adapter?.enabled ?? false) ? "󰂲" : root.btConnected.length > 0 ? "󰂱" : "󰂯"
            label: root.btConnected.length > 0 ? root.btConnected[0].name : "Bluetooth"
            visible: !!root.adapter
            onClicked: Quickshell.execDetached(["blueman-manager"])
        }

        PillButton {
            icon: Vpn.connected ? "󰦝" : "󰦞"
            label: Vpn.connected ? Vpn.relay || "Mullvad" : Vpn.state === "down" ? "VPN down" : "Mullvad"
            active: Vpn.connected
            visible: Vpn.state !== "absent"
            enabled: Vpn.state !== "down"
            onClicked: Vpn.toggle()
        }
    }

    Flow {
        width: parent.width
        spacing: 6

        Repeater {
            model: [
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

            PillButton {
                id: profile

                required property var modelData

                icon: modelData.icon
                label: modelData.label
                active: PowerProfiles.profile === modelData.id
                visible: modelData.id !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile
                onClicked: PowerProfiles.profile = profile.modelData.id
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
