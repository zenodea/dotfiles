pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    readonly property string id: "run"
    readonly property string label: "Run"
    readonly property string hint: "Run a shell command"
    readonly property string prefix: "!"
    readonly property string tag: "Shell"
    readonly property bool scoped: true
    readonly property bool live: true
    readonly property bool fleeting: true
    readonly property string glyph: "\u{f018d}"
    readonly property var terminal: ["ghostty", "-e"]
    readonly property int cap: 500

    property var answers: []
    property var history: []
    property string asked: ""

    property bool showing: false
    property string command: ""
    property string queued: ""
    property string text: ""
    property var pending: []
    property int lines: 0
    property bool capped: false
    property int code: 0
    property real started: 0
    property real took: 0
    readonly property bool running: work.running

    function ask(query: string): void {
        asked = query.trim();
        answers = (asked ? [
                {
                    kind: "run",
                    name: asked,
                    title: asked,
                    sub: "Enter shows the output here"
                }
            ] : []).concat(history.filter(h => h !== asked && h.includes(asked)).slice(0, 30).map(h => ({
                    kind: "run",
                    name: h,
                    title: h,
                    tag: "History",
                    past: true
                })));
    }

    function remember(wanted: string): void {
        history = [wanted].concat(history.filter(h => h !== wanted)).slice(0, 50);
        store.setText(JSON.stringify(history));
        ask(asked);
    }

    function forget(wanted: string): void {
        history = history.filter(h => h !== wanted);
        store.setText(JSON.stringify(history));
        ask(asked);
    }

    function activate(item: var): void {
        start(item.name);
    }

    function actions(item: var): var {
        const found = [
            {
                label: "Run",
                stay: true,
                run: () => root.start(item.name)
            },
            {
                label: "Run in terminal",
                run: () => {
                    root.remember(item.name);
                    Quickshell.execDetached(terminal.concat(["sh", "-c", `${item.name}; exec "$SHELL"`]));
                }
            },
            {
                label: "Run in background",
                run: () => {
                    root.remember(item.name);
                    Quickshell.execDetached(["sh", "-c", item.name]);
                }
            }
        ];
        if (item.past)
            found.push({
                label: "Forget",
                stay: true,
                run: () => root.forget(item.name)
            });
        return found;
    }

    function start(wanted: string): void {
        remember(wanted);
        showing = true;
        if (work.running) {
            queued = wanted;
            work.running = false;
            return;
        }
        command = wanted;
        text = "";
        pending = [];
        lines = 0;
        capped = false;
        code = 0;
        took = 0;
        started = Date.now();
        work.running = true;
    }

    function stop(): void {
        work.running = false;
    }

    function dismiss(): void {
        showing = false;
    }

    function copy(): void {
        Quickshell.execDetached(["wl-copy", text.slice(0, 100000)]);
        Notices.show("Run", "Output copied", glyph);
    }

    function flush(): void {
        if (!pending.length)
            return;
        text += (text ? "\n" : "") + pending.join("\n");
        pending = [];
    }

    Component.onCompleted: {
        try {
            const saved = JSON.parse(store.text() || "[]");
            history = Array.isArray(saved) ? saved : [];
        } catch (e) {
            history = [];
        }
    }

    FileView {
        id: store

        path: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/dotfiles/palette-run.json`
        blockLoading: true
        printErrors: false
    }

    Timer {
        id: soon

        interval: 30
        onTriggered: root.flush()
    }

    Process {
        id: work

        command: ["sh", "-c", `exec 2>&1 </dev/null; ${root.command}`]
        workingDirectory: Quickshell.env("HOME")
        onExited: exitCode => {
            root.flush();
            root.code = exitCode;
            root.took = (Date.now() - root.started) / 1000;
            if (!root.queued)
                return;
            const next = root.queued;
            root.queued = "";
            root.start(next);
        }

        stdout: SplitParser {
            onRead: line => {
                if (root.capped)
                    return;
                if (root.lines >= root.cap) {
                    root.capped = true;
                    root.pending.push(`… stopped after ${root.cap} lines`);
                    work.running = false;
                } else {
                    root.lines++;
                    root.pending.push(line.slice(line.lastIndexOf("\r") + 1).replace(/\x1b\[[0-9;?]*[ -\/]*[@-~]/g, "").slice(0, 2000));
                }
                if (!soon.running)
                    soon.start();
            }
        }
    }
}
