pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    readonly property string id: "files"
    readonly property string label: "Files"
    readonly property string hint: "Search your home folder"
    readonly property string prefix: "/"
    readonly property string tag: "File"
    readonly property bool scoped: true
    readonly property bool live: true
    readonly property bool fleeting: true
    readonly property bool enabled: Tools.has("fd")
    readonly property string glyph: "\u{f0968}"
    readonly property string home: Quickshell.env("HOME")

    property var answers: []
    property var found: []
    property string asked: ""

    function ask(query: string): void {
        asked = query.trim();
        if (asked.length > 1) {
            soon.restart();
            return;
        }
        soon.stop();
        answers = [];
    }

    function ranked(): var {
        const q = asked.toLowerCase();
        const score = item => {
            const name = item.title.toLowerCase();
            const at = name.indexOf(q);
            const fit = name === q ? 300 : at === 0 ? 200 : at > 0 && " -_.".includes(name[at - 1]) ? 150 : 100;
            return fit + (item.tag === "Folder" ? 20 : 0) - item.name.split("/").length * 3 - name.length * 0.2;
        };
        return found.map(item => ({
                    item,
                    score: score(item)
                })).sort((a, b) => b.score - a.score).slice(0, 50).map(s => s.item);
    }

    function activate(item: var): void {
        Quickshell.execDetached(["xdg-open", item.name]);
    }

    function actions(item: var): var {
        return [
            {
                label: "Open",
                run: () => Quickshell.execDetached(["xdg-open", item.name])
            },
            {
                label: "Open folder",
                run: () => Quickshell.execDetached(["xdg-open", item.name.replace(/\/[^\/]*\/?$/, "") || "/"])
            },
            {
                label: "Copy path",
                run: () => Quickshell.execDetached(["wl-copy", item.name])
            }
        ];
    }

    Timer {
        id: soon

        interval: 80
        onTriggered: {
            if (work.running) {
                work.running = false;
                return;
            }
            root.found = [];
            work.pattern = root.asked;
            work.running = true;
        }
    }

    Timer {
        id: flush

        interval: 60
        onTriggered: root.answers = root.ranked()
    }

    Process {
        id: work

        property string pattern: ""

        command: ["fd", "--max-results", "400", "--ignore-case", "--fixed-strings", "--", pattern, root.home]
        onExited: {
            if (pattern === root.asked)
                flush.restart();
            else if (root.asked.length > 1)
                soon.restart();
        }

        stdout: SplitParser {
            onRead: line => {
                if (!line || work.pattern !== root.asked)
                    return;
                const path = line.replace(/\/$/, "");
                const cut = path.lastIndexOf("/");
                root.found.push({
                    kind: "file",
                    name: path,
                    image: line.endsWith("/") ? Icons.folder(path.slice(cut + 1)) : Icons.file(path.slice(cut + 1)),
                    title: path.slice(cut + 1),
                    sub: path.slice(0, cut).replace(root.home, "~"),
                    tag: line.endsWith("/") ? "Folder" : "File"
                });
                if (!flush.running)
                    flush.start();
            }
        }
    }
}
