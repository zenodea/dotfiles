pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string stateDir: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/dotfiles`
    readonly property int keep: 100
    readonly property var defaults: ({
            model: "default",
            effort: "default",
            mode: "ask"
        })

    property bool ready: false
    property string provider: "claude"
    property var setups: ({})
    property string last: ""
    property var sessions: []

    readonly property var setup: Object.assign({}, defaults, setups[provider])

    function setProvider(name: string): void {
        provider = name;
        save();
    }

    function configure(key: string, value: string): void {
        setups = Object.assign({}, setups, {
            [provider]: Object.assign({}, setup, {
                [key]: value
            })
        });
        save();
    }

    function tidy(title: string): string {
        return title.replace(/\s+/g, " ").trim().slice(0, 80);
    }

    function rename(id: string, title: string): void {
        const name = tidy(title);
        if (name === "")
            return;
        sessions = sessions.map(s => s.id === id ? Object.assign({}, s, {
            title: name
        }) : s);
        save();
    }

    function forget(id: string): void {
        sessions = sessions.filter(s => s.id !== id);
        if (last === id)
            last = "";
        save();
    }

    function setLast(id: string): void {
        last = id;
        save();
    }

    function remember(id: string, title: string): void {
        const existing = sessions.find(s => s.id === id);
        sessions = [
            {
                id,
                title: existing?.title ?? (tidy(title) || "Untitled"),
                updated: Date.now(),
                provider: existing?.provider ?? provider
            }
        ].concat(sessions.filter(s => s.id !== id)).slice(0, keep);
        last = id;
        save();
    }

    function save(): void {
        if (!ready)
            return;
        adapter.provider = provider;
        adapter.setups = setups;
        adapter.last = last;
        adapter.sessions = sessions;
        file.writeAdapter();
    }

    FileView {
        id: file

        path: `${root.stateDir}/agent.json`
        printErrors: false
        onLoaded: {
            root.provider = adapter.provider;
            root.setups = adapter.setups ?? {};
            root.sessions = adapter.sessions ?? [];
            root.last = adapter.last;
            root.ready = true;
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                root.ready = true;
        }

        JsonAdapter {
            id: adapter

            property string provider: "claude"
            property var setups: ({})
            property string last: ""
            property var sessions: []
        }
    }
}
