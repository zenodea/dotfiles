import QtQuick
import Quickshell.Networking
import qs.style
import qs.widgets

BarButton {
    id: root

    readonly property var device: Networking.devices.values.find(d => d.connected) ?? null
    readonly property bool wifi: device?.type === DeviceType.Wifi
    readonly property var network: device?.networks?.values?.find(n => n.connected) ?? null
    readonly property int strength: network?.signalStrength ?? 0

    readonly property var wifiRamp: ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]

    icon: {
        if (!device)
            return "󰤭";
        if (!wifi)
            return "󰈀";
        if (strength <= 0)
            return "󰖩";
        return wifiRamp[Math.min(wifiRamp.length - 1, Math.floor(strength / 100 * wifiRamp.length))];
    }
    iconColour: device ? Theme.fg : Theme.red

    title: {
        if (!device)
            return "Disconnected";
        return wifi ? network?.name ?? "Wi-Fi" : "Ethernet";
    }

    popoutContent: Component {
        Column {
            spacing: 3

            PopoutTitle {
                text: root.title
            }

            PopoutLabel {
                text: root.device ? "" : "No connection"
            }

            PopoutRow {
                visible: !!root.device
                label: "Interface"
                value: root.device?.name ?? ""
            }

            PopoutRow {
                visible: !!root.device?.address
                label: "Address"
                value: root.device?.address ?? ""
            }

            PopoutRow {
                visible: root.wifi && root.strength > 0
                label: "Signal"
                value: `${root.strength}%`
            }

            PopoutRow {
                visible: !root.wifi && (root.device?.linkSpeed ?? 0) > 0
                label: "Link"
                value: `${root.device?.linkSpeed ?? 0} Mb/s`
            }
        }
    }
}
