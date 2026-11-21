pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string id: "scripts"
    readonly property string label: "Scripts"
    readonly property string tag: "Script"
    readonly property string verb: "Run"
    readonly property string glyph: "\u{f0bc1}"
    readonly property string folder: `${Quickshell.shellDir}/commands`

    property var entries: []

    function refresh(): void {
        lister.running = true;
    }

    function results(query: string): var {
        const q = query.trim().toLowerCase();
        return entries.filter(e => !q || e.title.toLowerCase().includes(q));
    }

    function activate(item: var): void {
        Quickshell.execDetached([item.name]);
    }

    Process {
        id: lister

        running: true
        command: ["sh", "-c", `for f in "$1"/*; do [ -f "$f" ] && [ -x "$f" ] || continue; printf '%s\\t%s\\t%s\\n' "$f" "$(sed -n 's/^# *title: *//p' "$f" | head -n 1)" "$(sed -n 's/^# *sub: *//p' "$f" | head -n 1)"; done`, "sh", root.folder]

        stdout: StdioCollector {
            onStreamFinished: {
                const found = text.split("\n").filter(Boolean).map(line => {
                    const [path, title, sub] = line.split("\t");
                    return {
                        kind: "script",
                        name: path,
                        title: title || path.slice(path.lastIndexOf("/") + 1),
                        sub: sub ?? ""
                    };
                });
                if (JSON.stringify(found) !== JSON.stringify(root.entries))
                    root.entries = found;
            }
        }
    }
}
