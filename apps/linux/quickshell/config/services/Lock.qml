pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

Singleton {
    id: root

    // locked holds the session lock; shut drives the frame closing over the screen
    property bool locked: false
    property bool shut: false
    property string buffer: ""
    property int fails: 0
    property bool fingerprint: false

    readonly property bool checking: pam.active
    readonly property string user: Quickshell.env("USER") ?? ""
    readonly property string shotDir: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/dotfiles-lock`

    signal failed

    function lock(): void {
        if (locked || capture.running)
            return;
        capture.command = ["sh", "-c", 'mkdir -p "$0"; for o in "$@"; do grim -l 0 -o "$o" "$0/$o.png" & done; wait', shotDir, ...Quickshell.screens.map(s => s.name)];
        capture.running = true;
    }

    function type(text: string): void {
        if (!pam.active)
            buffer += text;
    }

    function erase(all: bool): void {
        if (!pam.active)
            buffer = all ? "" : buffer.slice(0, -1);
    }

    function submit(): void {
        if (buffer !== "" && !pam.active)
            pam.start();
    }

    function release(): void {
        buffer = "";
        fails = 0;
        locked = false;
        Quickshell.execDetached(["rm", "-rf", shotDir]);
    }

    Process {
        id: capture

        onExited: {
            root.locked = true;
            root.shut = true;
            enrolled.running = true;
        }
    }

    Process {
        id: enrolled

        command: ["sh", "-c", 'fprintd-list "$USER" 2> /dev/null | grep -q " - #"']
        onExited: code => {
            if (code === 0 && root.shut) {
                root.fingerprint = true;
                finger.start();
            }
        }
    }

    PamContext {
        id: finger

        config: "fingerprint"
        configDirectory: `${Quickshell.shellDir}/pam`

        onCompleted: result => {
            if (result === PamResult.Success)
                root.shut = false;
            else if (root.shut)
                retry.start();
        }
    }

    Timer {
        id: retry

        interval: 1000
        onTriggered: {
            if (root.shut)
                finger.start();
        }
    }

    onShutChanged: {
        if (!shut) {
            fingerprint = false;
            finger.active = false;
        }
    }

    PamContext {
        id: pam

        onPamMessage: {
            if (responseRequired)
                respond(root.buffer);
        }

        onCompleted: result => {
            root.buffer = "";
            if (result === PamResult.Success) {
                root.shut = false;
            } else {
                root.fails++;
                root.failed();
            }
        }
    }
}
