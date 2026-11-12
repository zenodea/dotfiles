pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import qs.style

Singleton {
    id: root

    property var users: []
    property int index: 0
    property string buffer: ""
    property int fails: 0
    property bool checking: false
    property bool done: false
    property bool fingerprint: false
    property bool prompted: false
    property bool scanned: false
    property bool pending: false

    readonly property string user: users[index] ?? ""
    readonly property bool preview: !Greetd.available
    readonly property string passwordFlag: `${Quickshell.env("XDG_RUNTIME_DIR")}/greeter-password`
    readonly property string themeDir: "/var/lib/greeter-themes"
    property string defaultTheme: ""

    signal failed

    function snapshotTheme(): string {
        const colours = {};
        for (const key of ["bg", "surface", "muted", "fg", "fgBright", "accent", "blue", "red", "green", "yellow", "orange", "purple"])
            colours[key] = `${Theme[key]}`;
        return JSON.stringify({
            colours,
            font: {
                mono: Theme.monoRequested
            }
        });
    }

    function applyTheme(data: string): void {
        if (!data)
            return;
        Theme.load(data);
        Theme.fade = true;
    }

    Component.onCompleted: defaultTheme = snapshotTheme()

    function type(text: string): void {
        if (!checking)
            buffer += text;
    }

    function erase(all: bool): void {
        if (!checking)
            buffer = all ? "" : buffer.slice(0, -1);
    }

    function cycle(step: int): void {
        if (checking || users.length < 2)
            return;
        index = (index + step + users.length) % users.length;
        buffer = "";
        fails = 0;
        usePassword(false);
    }

    function submit(): void {
        if (buffer === "" || checking || !user)
            return;
        checking = true;
        if (preview)
            rejectPreview.start();
        else if (prompted)
            answer();
        else
            usePassword(true);
    }

    function answer(): void {
        prompted = false;
        Greetd.respond(buffer);
    }

    function reject(): void {
        buffer = "";
        checking = false;
        fails++;
        failed();
    }

    function usePassword(on: bool): void {
        if (preview)
            return;
        flag.command = on ? ["touch", passwordFlag] : ["rm", "-f", passwordFlag];
        flag.running = true;
    }

    function restart(): void {
        fingerprint = false;
        prompted = false;
        scanned = false;
        if (!user)
            return;
        if (Greetd.state === GreetdState.Inactive) {
            Greetd.createSession(user);
        } else {
            pending = true;
            Greetd.cancelSession();
        }
    }

    onBufferChanged: {
        if (buffer === "" && prompted && scanned && !checking)
            restart();
    }

    FileView {
        path: "/etc/passwd"
        onLoaded: {
            root.users = text().split("\n").map(line => line.split(":")).filter(f => Number(f[2]) >= 1000 && Number(f[2]) < 60000 && !/(nologin|false)$/.test(f[6] ?? "")).map(f => f[0]);
            root.usePassword(false);
        }
    }

    FileView {
        path: root.user ? `${root.themeDir}/${root.user}.json` : ""
        onLoaded: root.applyTheme(text())
        onLoadFailed: root.applyTheme(root.defaultTheme)
    }

    Process {
        id: flag

        onExited: root.restart()
    }

    Connections {
        function onAuthMessage(message: string, error: bool, responseRequired: bool): void {
            if (responseRequired) {
                root.fingerprint = false;
                if (root.checking)
                    root.answer();
                else if (root.scanned && root.buffer === "")
                    root.restart();
                else
                    root.prompted = true;
            } else if (!error) {
                root.fingerprint = true;
                root.scanned = true;
            }
        }

        function onAuthFailure(): void {
            root.reject();
            root.usePassword(false);
        }

        function onError(): void {
            root.reject();
            root.usePassword(false);
        }

        function onReadyToLaunch(): void {
            root.fingerprint = false;
            root.done = true;
            launch.start();
        }

        function onStateChanged(): void {
            if (root.pending && Greetd.state === GreetdState.Inactive) {
                root.pending = false;
                Greetd.createSession(root.user);
            }
        }

        target: Greetd
    }

    Timer {
        id: launch

        interval: Metrics.lockDuration
        onTriggered: Greetd.launch(["start-hyprland"], ["XDG_SESSION_TYPE=wayland", "XDG_CURRENT_DESKTOP=Hyprland", "XDG_SESSION_DESKTOP=Hyprland"], true)
    }

    Timer {
        id: rejectPreview

        interval: 600
        onTriggered: root.reject()
    }
}
