pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.services
import qs.widgets

Column {
    id: root

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool powered: adapter?.enabled ?? false
    readonly property var devices: Bluetooth.devices.values.filter(d => d.paired || d.connected).sort((a, b) => b.connected - a.connected)

    visible: !!adapter
    spacing: 2

    Toggle {
        width: parent.width
        icon: root.powered ? "󰂯" : "󰂲"
        label: "Bluetooth"
        checked: root.powered
        onToggled: root.adapter.enabled = !root.adapter.enabled
    }

    Repeater {
        model: ScriptModel {
            values: root.powered ? root.devices : []
        }

        PickRow {
            id: entry

            required property BluetoothDevice modelData

            readonly property bool busy: modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting

            width: root.width
            icon: modelData.connected ? "󰂱" : "󰂯"
            label: modelData.name
            detail: busy ? "…" : !modelData.connected ? "" : modelData.batteryAvailable ? `${Math.round(modelData.battery * 100)}%` : "Connected"
            active: modelData.connected
            onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
        }
    }

    PickRow {
        width: parent.width
        visible: root.powered
        icon: "󰂰"
        label: "Pair new device…"
        onClicked: {
            Quickshell.execDetached(["blueman-manager"]);
            Panels.close();
        }
    }
}
