pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    readonly property string id: "symbols"
    readonly property string label: "Symbols"
    readonly property string hint: "Search emoji and symbols"
    readonly property string prefix: ":"
    readonly property string tag: "Symbol"
    readonly property string verb: "Copy"
    readonly property bool scoped: true
    readonly property string glyph: "\u{f01f2}"

    property var entries: []

    function results(query: string): var {
        const q = query.trim().toLowerCase();
        return q ? entries.filter(e => e.title.includes(q)) : entries;
    }

    function activate(item: var): void {
        Quickshell.execDetached(["wl-copy", item.name]);
        Notices.show(item.name, "Copied", glyph);
    }

    Process {
        running: true
        command: ["python3", `${Quickshell.shellDir}/scripts/symbols.py`]

        stdout: StdioCollector {
            onStreamFinished: root.entries = text.split("\n").filter(Boolean).map(line => {
                const tab = line.indexOf("\t");
                const char = line.slice(0, tab);
                return {
                    kind: "symbol",
                    name: char,
                    title: line.slice(tab + 1),
                    mark: char,
                    tag: `U+${char.codePointAt(0).toString(16).toUpperCase()}`
                };
            })
        }
    }
}
