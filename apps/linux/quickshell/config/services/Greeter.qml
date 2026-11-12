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
    property string session: ""
    property string want: ""
    property bool scanned: false
    property bool stopping: false
    property string defaultTheme: ""

    readonly property string user: users[index] ?? ""
    readonly property bool preview: !Greetd.available
    readonly property string passwordFlag: `${Quickshell.env("XDG_RUNTIME_DIR")}/greeter-password`
    readonly property string themeDir: "/var/lib/greeter-themes"

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
        want = "finger";
        stop();
        kick();
    }

    function submit(): void {
        if (buffer === "" || checking || !user)
            return;
        checking = true;
        if (preview) {
            rejectPreview.start();
            return;
        }
        want = "password";
        stop();
        kick();
    }

    function stop(): void {
        if (session !== "finger")
            return;
        stopping = true;
        flag.setText("1");
    }

    function kick(): void {
        if (preview || session !== "" || !want || !user)
            return;
        retry.stop();
        session = want;
        scanned = false;
        flag.setText(want === "password" ? "1" : "");
        Greetd.createSession(user);
    }

    function ended(): void {
        const was = session;
        session = "";
        fingerprint = false;
        if (was === "password") {
            buffer = "";
            checking = false;
            fails++;
            failed();
            want = "finger";
            kick();
        } else if (stopping) {
            stopping = false;
            kick();
        } else if (scanned) {
            retry.start();
        } else {
            want = "";
        }
    }

    Component.onCompleted: defaultTheme = snapshotTheme()

    FileView {
        path: "/etc/passwd"
        onLoaded: {
            root.users = text().split("\n").map(line => line.split(":")).filter(f => Number(f[2]) >= 1000 && Number(f[2]) < 60000 && !/(nologin|false)$/.test(f[6] ?? "")).map(f => f[0]);
            root.want = "finger";
            root.kick();
        }
    }

    FileView {
        path: root.user ? `${root.themeDir}/${root.user}.json` : ""
        onLoaded: root.applyTheme(text())
        onLoadFailed: root.applyTheme(root.defaultTheme)
    }

    FileView {
        id: flag

        path: root.passwordFlag
        blockWrites: true
        printErrors: false
    }

    Connections {
        function onAuthMessage(message: string, error: bool, responseRequired: bool): void {
            if (responseRequired) {
                if (root.session === "password" && root.checking)
                    Greetd.respond(root.buffer);
            } else if (!error && root.session === "finger") {
                root.fingerprint = true;
                root.scanned = true;
            }
        }

        function onAuthFailure(): void {
            root.ended();
        }

        function onError(): void {
            root.ended();
        }

        function onReadyToLaunch(): void {
            root.session = "";
            root.fingerprint = false;
            root.done = true;
            launch.start();
        }

        target: Greetd
    }

    Timer {
        id: retry

        interval: 1000
        onTriggered: root.kick()
    }

    Timer {
        id: launch

        interval: Metrics.lockDuration
        onTriggered: Greetd.launch(["start-hyprland"], ["XDG_SESSION_TYPE=wayland", "XDG_CURRENT_DESKTOP=Hyprland", "XDG_SESSION_DESKTOP=Hyprland"], true)
    }

    Timer {
        id: rejectPreview

        interval: 600
        onTriggered: {
            root.buffer = "";
            root.checking = false;
            root.fails++;
            root.failed();
        }
    }
}
