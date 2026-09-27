import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.style
import qs.widgets

BarButton {
    id: root

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: adapter?.enabled ?? false
    readonly property var connected: Bluetooth.devices.values.filter(d => d.connected)

    shown: !!adapter
    icon: !enabled ? "󰂲" : connected.length > 0 ? "󰂱" : "󰂯"
    iconColour: !enabled ? Theme.muted : connected.length > 0 ? Theme.blue : Theme.fg

    title: !enabled ? "Bluetooth off" : connected.length > 0 ? `${connected.length} connected` : "Bluetooth on"

    popoutContent: Component {
        Column {
            spacing: 3

            PopoutTitle {
                text: root.title
            }

            PopoutLabel {
                text: root.enabled && root.connected.length === 0 ? "No devices connected" : ""
            }

            Repeater {
                model: root.connected

                PopoutRow {
                    required property var modelData

                    label: modelData.name
                    value: modelData.batteryAvailable ? `${Math.round(modelData.battery * 100)}%` : "connected"
                    valueColour: modelData.batteryAvailable && modelData.battery <= 0.2 ? Theme.red : Theme.fg
                }
            }

            PopoutLabel {
                text: root.adapter?.discovering ? "Scanning…" : ""
            }
        }
    }

    onClicked: Quickshell.execDetached(["blueman-manager"])
}
