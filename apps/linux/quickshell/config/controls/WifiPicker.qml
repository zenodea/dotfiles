pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Networking
import qs.services
import qs.style
import qs.widgets

Column {
    id: root

    required property bool scanning

    readonly property var device: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var networks: [...(device?.networks?.values ?? [])].filter(n => n.name !== "").sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength)).slice(0, 8)

    property string asking: ""
    property string error: ""
    property var connecting: null

    function join(network: var, psk: string): void {
        asking = "";
        error = "";
        connecting = network;
        if (psk === "")
            network.connect();
        else
            network.connectWithPsk(psk);
    }

    function failed(reason: int): void {
        const network = connecting;
        connecting = null;
        if (!network)
            return;
        error = `Connection failed: ${ConnectionFailReason.toString(reason)}. Please retry.`;
        if (network.security !== WifiSecurityType.Open && network.security !== WifiSecurityType.Owe)
            asking = network.name;
    }

    function pick(network: var): void {
        if (network.stateChanging)
            return;
        error = "";
        if (network.connected) {
            asking = "";
            network.disconnect();
        } else if (network.known || network.security === WifiSecurityType.Open || network.security === WifiSecurityType.Owe) {
            join(network, "");
        } else {
            asking = asking === network.name ? "" : network.name;
        }
    }

    spacing: 2

    onScanningChanged: {
        asking = "";
        error = "";
    }

    onAskingChanged: {
        if (asking !== "")
            Panels.controlsByHover = false;
    }

    Connections {
        target: root.connecting

        function onConnectionFailed(reason: int): void {
            root.failed(reason);
        }

        function onConnectedChanged(): void {
            if (root.connecting?.connected) {
                root.connecting = null;
                root.asking = "";
                root.error = "";
            }
        }
    }

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

            function submit(): void {
                if (password.text === "" || modelData.stateChanging)
                    return;
                const psk = password.text;
                password.text = "";
                Nav.refocus();
                root.join(modelData, psk);
            }

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
                    anchors.rightMargin: connectButton.width + 9
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    color: Theme.fgBright
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                    clip: true
                    focus: entry.asking
                    onVisibleChanged: {
                        text = "";
                        if (visible)
                            forceActiveFocus();
                    }
                    Keys.onEscapePressed: {
                        root.asking = "";
                        Nav.refocus();
                    }
                    onAccepted: entry.submit()

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: password.text === ""
                        text: "Password (Enter to connect)…"
                        color: Theme.alpha(Theme.muted, 0.7)
                        font: password.font
                        renderType: Text.NativeRendering
                    }
                }

                PillButton {
                    id: connectButton

                    anchors.right: parent.right
                    label: "Connect"
                    enabled: password.text !== "" && !entry.modelData.stateChanging
                    onClicked: entry.submit()
                }
            }
        }
    }

    Label {
        width: parent.width
        visible: text !== ""
        text: root.error
        color: Theme.red
        font.pixelSize: 11
        wrapMode: Text.Wrap
    }
}
