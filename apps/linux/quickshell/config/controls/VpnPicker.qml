pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.widgets

Column {
    id: root

    visible: Vpn.available
    spacing: 2

    Toggle {
        width: parent.width
        enabled: Vpn.state !== "down"
        icon: Vpn.connected ? "󰦝" : "󰦞"
        label: Vpn.state === "down" ? "Mullvad (daemon down)" : "Mullvad"
        checked: Vpn.connected
        onToggled: Vpn.toggle()
    }

    Repeater {
        model: ScriptModel {
            values: Vpn.state === "down" ? [] : Vpn.recents
        }

        PickRow {
            required property var modelData

            width: root.width
            icon: "󰍎"
            label: modelData.label
            detail: active ? "Connected" : ""
            active: Vpn.connected && Vpn.code === modelData.code
            onClicked: Vpn.pick(modelData.code)
        }
    }
}
