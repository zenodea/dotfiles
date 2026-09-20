pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    readonly property string script: `${Quickshell.shellDir}/scripts/clipboard.sh`
    readonly property string store: `${Quickshell.env("XDG_CACHE_HOME") || `${Quickshell.env("HOME")}/.cache`}/dotfiles/clipboard/entries`
    readonly property bool available: Tools.has("wl-copy")

    property var entries: []

    function refresh(): void {
        if (available)
            lister.running = true;
    }

    function copy(id: string): void {
        Quickshell.execDetached(["bash", root.script, "copy", id]);
    }

    function path(id: string): string {
        return `file://${root.store}/${id}`;
    }

    function forget(id: string): void {
        Quickshell.execDetached(["bash", root.script, "delete", id]);
        refreshSoon.restart();
    }

    function wipe(): void {
        Quickshell.execDetached(["bash", root.script, "wipe"]);
        refreshSoon.restart();
    }

    Process {
        running: root.available
        command: ["bash", root.script, "watch"]

        stdout: SplitParser {
            onRead: root.refresh()
        }
    }

    Process {
        id: lister

        running: root.available
        command: ["bash", root.script, "list"]

        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    if (!line)
                        continue;
                    const parts = line.split("\t");
                    if (parts.length < 4)
                        continue;
                    out.push({
                        id: parts[0],
                        kind: parts[1],
                        mime: parts[2],
                        preview: parts.slice(3).join("\t")
                    });
                }
                root.entries = out;
            }
        }
    }

    Timer {
        id: refreshSoon

        interval: 120
        onTriggered: root.refresh()
    }
}
