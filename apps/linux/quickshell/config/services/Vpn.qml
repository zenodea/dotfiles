pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string state: "absent"
    property string relay: ""
    property string location: ""
    property string city: ""

    readonly property bool available: state !== "absent"
    readonly property bool connected: state === "connected"
    readonly property string code: relay.split("-").slice(0, 2).join(" ")
    readonly property alias recents: store.recents

    onCodeChanged: {
        if (!connected || code === "")
            return;
        store.recents = [
            {
                code: code,
                label: location
            },
            ...store.recents.filter(r => r.code !== code)
        ].slice(0, 5);
    }

    function pick(code: string): void {
        Quickshell.execDetached(["sh", "-c", 'mullvad relay set location "$@" && mullvad connect', "sh", ...code.split(" ")]);
    }

    function toggle(): void {
        Quickshell.execDetached(["bash", `${Quickshell.shellDir}/scripts/vpn.sh`, "toggle"]);
    }

    FileView {
        path: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/dotfiles/vpn-recents.json`
        printErrors: false
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: store

            property var recents: []
        }
    }

    Process {
        running: true
        command: ["bash", `${Quickshell.shellDir}/scripts/vpn.sh`, "watch"]

        stdout: SplitParser {
            onRead: data => {
                const d = JSON.parse(data);
                root.state = d.state;
                root.location = d.location;
                root.city = d.city ?? "";
                root.relay = d.relay;
            }
        }
    }
}
