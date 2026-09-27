pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string stateDir: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/dotfiles`
    readonly property var models: ["default", "haiku", "sonnet", "opus"]
    readonly property int keep: 30

    property string model: "default"
    property string last: ""
    property var sessions: []

    function setModel(name: string): bool {
        if (!models.includes(name))
            return false;
        model = name;
        save();
        return true;
    }

    function setLast(id: string): void {
        last = id;
        save();
    }

    // moves a thread to the top of the list, keeping its first title
    function remember(id: string, title: string): void {
        const existing = sessions.find(s => s.id === id);
        const name = existing?.title ?? (title || "Untitled");
        sessions = [
            {
                id,
                title: name.replace(/\s+/g, " ").slice(0, 80),
                updated: Date.now()
            }
        ].concat(sessions.filter(s => s.id !== id)).slice(0, keep);
        last = id;
        save();
    }

    function save(): void {
        adapter.model = model;
        adapter.last = last;
        adapter.sessions = sessions;
        file.writeAdapter();
    }

    FileView {
        id: file

        path: `${root.stateDir}/agent.json`
        printErrors: false
        onLoaded: {
            root.model = root.models.includes(adapter.model) ? adapter.model : "default";
            root.sessions = adapter.sessions ?? [];
            root.last = adapter.last;
        }

        JsonAdapter {
            id: adapter

            property string model: "default"
            property string last: ""
            property var sessions: []
        }
    }
}
