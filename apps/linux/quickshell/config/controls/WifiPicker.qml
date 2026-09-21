pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Networking
import qs.style
import qs.widgets

Column {
    id: root

    required property bool scanning

    readonly property var device: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var networks: [...(device?.networks?.values ?? [])].filter(n => n.name !== "").sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength)).slice(0, 8)

    property string asking: ""

    function pick(network: var): void {
        if (network.connected)
            network.disconnect();
        else if (network.known || network.security === WifiSecurityType.Open)
            network.connect();
        else
            asking = asking === network.name ? "" : network.name;
    }

    spacing: 2

    onScanningChanged: asking = ""

    Binding {
        target: root.device
        property: "scannerEnabled"
        value: root.scanning && Networking.wifiEnabled
        when: !!root.device
    }

    Toggle {
        width: parent.width
        icon: Networking.wifiEnabled ? "󰖩" : "󰖪"
        label: "Wi-Fi"
        checked: Networking.wifiEnabled
        onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
    }

    Repeater {
        model: ScriptModel {
            values: Networking.wifiEnabled ? root.networks : []
        }

        Column {
            id: entry

            required property var modelData

            readonly property bool asking: root.asking === modelData.name

            width: root.width

            PickRow {
                width: parent.width
                icon: ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"][Math.min(4, Math.floor(entry.modelData.signalStrength * 5))]
                label: entry.modelData.name
                detail: entry.modelData.connected ? "Connected" : entry.modelData.stateChanging ? "Connecting…" : entry.modelData.known ? "Saved" : entry.modelData.security === WifiSecurityType.Open ? "Open" : "󰌾"
                active: entry.modelData.connected
                onClicked: root.pick(entry.modelData)
            }

            Rectangle {
                width: parent.width
                height: 30
                visible: entry.asking
                color: Theme.alpha(Theme.fg, 0.06)

                TextInput {
                    id: password

                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    color: Theme.fgBright
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                    clip: true
                    focus: entry.asking
                    onVisibleChanged: {
                        if (visible)
                            forceActiveFocus();
                    }
                    Keys.onEscapePressed: root.asking = ""
                    onAccepted: {
                        if (text === "")
                            return;
                        entry.modelData.connectWithPsk(text);
                        root.asking = "";
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: password.text === ""
                        text: "Password…"
                        color: Theme.alpha(Theme.muted, 0.7)
                        font: password.font
                        renderType: Text.NativeRendering
                    }
                }
            }
        }
    }
}
