pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string state: "absent"
    property string relay: ""
    property string location: ""

    readonly property bool available: state !== "absent"
    readonly property bool connected: state === "connected"

    function toggle(): void {
        Quickshell.execDetached(["bash", `${Quickshell.shellDir}/scripts/mullvad.sh`, "toggle"]);
    }

    Process {
        running: true
        command: ["bash", `${Quickshell.shellDir}/scripts/mullvad.sh`, "watch"]

        stdout: SplitParser {
            onRead: data => {
                const d = JSON.parse(data);
                root.state = d.state;
                root.relay = d.relay;
                root.location = d.location;
            }
        }
    }
}
