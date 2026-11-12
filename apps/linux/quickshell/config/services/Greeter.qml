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
    property var sessions: []
    property string sessionId: ""
    property var picks: ({})
    property var saved: ({})
    property string buffer: ""
    property int fails: 0
    property bool checking: false
    property bool done: false
    property bool fingerprint: false
    property string phase: ""
    property string want: ""
    property bool scanned: false
    property bool stopping: false
    property string defaultTheme: ""
    property string fontPick: ""

    readonly property string user: users[index] ?? ""
    readonly property var session: sessions.find(s => s.id === sessionId) ?? null
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
        let theme;
        try {
            theme = JSON.parse(data);
        } catch (e) {
            return;
        }
        if (fontPick)
            theme.font = {
                mono: fontPick
            };
        Theme.load(JSON.stringify(theme));
        Theme.fade = true;
    }

    function preferredSession(): string {
        for (const id of [picks[user], saved.sessions?.[user], "hyprland"])
            if (id && sessions.some(s => s.id === id))
                return id;
        return sessions[0]?.id ?? "";
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
        if (checking || done || users.length < 2)
            return;
        index = (index + step + users.length) % users.length;
        sessionId = preferredSession();
        buffer = "";
        fails = 0;
        want = "finger";
        stop();
        kick();
    }

    function cycleSession(step: int): void {
        if (checking || done || sessions.length < 2)
            return;
        const i = Math.max(0, sessions.findIndex(s => s.id === sessionId));
        sessionId = sessions[(i + step + sessions.length) % sessions.length].id;
        picks = Object.assign({}, picks, {
            [user]: sessionId
        });
    }

    function submit(): void {
        if (buffer === "" || checking || done || !user)
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

    function power(action: string): void {
        if (preview || checking || done)
            return;
        if (action === "suspend") {
            Quickshell.execDetached(["systemctl", "suspend"]);
            return;
        }
        done = true;
        leave.command = ["systemctl", action];
        leave.start();
    }

    function stop(): void {
        if (phase !== "finger")
            return;
        stopping = true;
        flag.setText("1");
    }

    function kick(): void {
        if (preview || done || phase !== "" || !want || !user)
            return;
        retry.stop();
        phase = want;
        scanned = false;
        flag.setText(want === "password" ? "1" : "");
        Greetd.createSession(user);
    }

    function ended(): void {
        const was = phase;
        phase = "";
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

    function launch(): void {
        const desktops = (session?.desktops || "Hyprland").split(";").filter(Boolean);
        saved = Object.assign({}, saved, {
            user,
            sessions: Object.assign({}, saved.sessions, {
                [user]: sessionId
            })
        });
        stateFile.setText(JSON.stringify(saved));
        Greetd.launch(["/bin/sh", "-c", `exec ${session?.exec ?? "start-hyprland"}`], ["XDG_SESSION_TYPE=wayland", `XDG_CURRENT_DESKTOP=${desktops.join(":")}`, `XDG_SESSION_DESKTOP=${desktops[0]}`], true);
    }

    Component.onCompleted: {
        defaultTheme = snapshotTheme();
        try {
            saved = JSON.parse(stateFile.text() || "{}");
        } catch (e) {
            saved = {};
        }
        users = passwd.text().split("\n").map(line => line.split(":")).filter(f => Number(f[2]) >= 1000 && Number(f[2]) < 60000 && !/(nologin|false)$/.test(f[6] ?? "")).map(f => f[0]);
        index = Math.max(0, users.indexOf(saved.user));
        want = "finger";
        kick();
    }

    FileView {
        id: passwd

        path: "/etc/passwd"
        blockLoading: true
    }

    FileView {
        id: stateFile

        path: "/var/lib/greeter/state.json"
        blockLoading: true
        blockWrites: true
        printErrors: false
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

    Process {
        running: true
        command: ["bash", `${Quickshell.shellDir}/scripts/sessions.sh`]

        stdout: StdioCollector {
            onStreamFinished: {
                root.sessions = text.split("\n").filter(Boolean).map(line => {
                    const [id, name, exec, desktops] = line.split("\t");
                    return {
                        id,
                        name,
                        exec: exec.replace(/%[a-zA-Z]/g, "").trim(),
                        desktops: desktops || name
                    };
                });
                root.sessionId = root.preferredSession();
            }
        }
    }

    Process {
        running: true
        command: ["sh", "-c", 'for f in "$0"/*.json; do tr -d "\\n" < "$f"; echo; done', root.themeDir]

        stdout: StdioCollector {
            onStreamFinished: {
                const installed = Qt.fontFamilies();
                const fonts = [...new Set(text.split("\n").filter(Boolean).map(line => {
                        try {
                            return JSON.parse(line).font?.mono ?? "";
                        } catch (e) {
                            return "";
                        }
                    }).filter(font => font && installed.includes(font)))];
                if (fonts.length === 0)
                    return;
                root.fontPick = fonts[Math.floor(Math.random() * fonts.length)];
                Theme.monoRequested = root.fontPick;
            }
        }
    }

    Connections {
        function onAuthMessage(message: string, error: bool, responseRequired: bool): void {
            if (responseRequired) {
                if (root.phase === "password" && root.checking)
                    Greetd.respond(root.buffer);
            } else if (!error && root.phase === "finger") {
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
            root.phase = "";
            root.fingerprint = false;
            root.done = true;
            launchDelay.start();
        }

        target: Greetd
    }

    Timer {
        id: retry

        interval: 1000
        onTriggered: root.kick()
    }

    Timer {
        id: launchDelay

        interval: Metrics.lockDuration
        onTriggered: root.launch()
    }

    Timer {
        id: leave

        property var command: []

        interval: Metrics.lockDuration
        onTriggered: Quickshell.execDetached(command)
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
