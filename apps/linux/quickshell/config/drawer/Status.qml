pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.UPower
import qs.services
import qs.style
import qs.widgets

Grid {
    id: root

    readonly property var net: Networking.devices.values.find(d => d.connected) ?? null
    readonly property bool wifi: net?.type === DeviceType.Wifi
    readonly property var network: net?.networks?.values?.find(n => n.connected) ?? null

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property var paired: Bluetooth.devices.values.filter(d => d.connected)

    readonly property var battery: UPower.displayDevice
    readonly property int percent: Math.round((battery?.percentage ?? 0) <= 1 ? (battery?.percentage ?? 0) * 100 : battery.percentage)
    readonly property bool charging: battery?.state === UPowerDeviceState.Charging || battery?.state === UPowerDeviceState.FullyCharged

    function duration(seconds: real): string {
        if (!seconds || seconds <= 0)
            return "";
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        return h > 0 ? `${h}h ${m}m` : `${m}m`;
    }

    columns: 2
    spacing: 6

    readonly property real cell: (width - spacing) / 2

    component Tile: Rectangle {
        id: tile

        property string icon: ""
        property color iconColour: Theme.fg
        property string caption: ""
        property string value: ""

        width: root.cell
        height: 44
        color: Theme.alpha(Theme.fg, 0.05)

        Icon {
            id: glyph

            x: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            text: tile.icon
            color: tile.iconColour
            font.pixelSize: 16
        }

        Column {
            anchors.left: glyph.right
            anchors.leftMargin: 6
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Label {
                text: tile.caption.toUpperCase()
                color: Theme.muted
                font.pixelSize: 9
                font.letterSpacing: 1.2
            }

            Label {
                width: parent.width
                elide: Text.ElideRight
                text: tile.value
            }
        }
    }

    Tile {
        icon: !root.net ? "󰤭" : root.wifi ? "󰤨" : "󰈀"
        iconColour: root.net ? Theme.accent : Theme.red
        caption: root.wifi || !root.net ? "Wi-Fi" : "Ethernet"
        value: {
            if (!root.net)
                return "disconnected";
            return root.wifi ? root.network?.name ?? "connected" : root.net.name;
        }
    }

    Tile {
        visible: !!root.adapter
        icon: !root.adapter?.enabled ? "󰂲" : root.paired.length > 0 ? "󰂱" : "󰂯"
        iconColour: !root.adapter?.enabled ? Theme.muted : root.paired.length > 0 ? Theme.blue : Theme.fg
        caption: "Bluetooth"
        value: root.paired.length === 0 ? "no device" : root.paired.map(d => d.name).join(", ")
    }

    Tile {
        visible: Vpn.available
        icon: Vpn.connected ? "󰦝" : "󰦞"
        iconColour: Vpn.connected ? Theme.green : Vpn.state === "connecting" ? Theme.yellow : Theme.muted
        caption: "VPN"
        value: Vpn.connected ? Vpn.city || Vpn.location || Vpn.relay : Vpn.state === "down" ? "daemon down" : Vpn.state
    }

    Tile {
        visible: root.battery?.isLaptopBattery ?? false
        icon: root.charging ? "󰂄" : "󰁹"
        iconColour: root.charging ? Theme.green : root.percent <= 10 ? Theme.red : root.percent <= 20 ? Theme.yellow : Theme.fg
        caption: "Battery"
        value: {
            const left = root.duration(root.charging ? root.battery?.timeToFull ?? 0 : root.battery?.timeToEmpty ?? 0);
            const parts = [`${root.percent}%`];
            if (left)
                parts.push(root.charging ? `${left} to full` : left);
            return parts.join(" · ");
        }
    }
}
