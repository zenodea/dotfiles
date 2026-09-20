import QtQuick
import Quickshell
import qs.style
import qs.services
import qs.widgets

BarButton {
    id: root

    readonly property bool down: Vpn.state === "down"

    shown: Vpn.state !== "absent"
    icon: Vpn.connected ? "󰦝" : "󰦞"
    iconColour: Vpn.connected ? Theme.green : Vpn.state === "connecting" ? Theme.yellow : down ? Theme.alpha(Theme.muted, 0.6) : Theme.muted

    label: Vpn.connected ? Vpn.city || Vpn.location : ""

    title: Vpn.connected ? "Mullvad" : down ? "Mullvad daemon down" : Vpn.state === "connecting" ? "Connecting…" : "Mullvad disconnected"

    popoutContent: Component {
        Column {
            spacing: 3

            PopoutTitle {
                text: root.title
            }

            PopoutLabel {
                text: root.down ? "systemctl start mullvad-daemon" : ""
            }

            PopoutRow {
                visible: Vpn.connected
                label: "Relay"
                value: Vpn.relay
            }

            PopoutRow {
                visible: Vpn.connected && Vpn.location !== ""
                label: "Location"
                value: Vpn.location
            }

            PopoutLabel {
                text: !Vpn.connected && !root.down ? "Click to connect" : ""
            }
        }
    }

    onClicked: {
        if (!down)
            Vpn.toggle();
    }
}
