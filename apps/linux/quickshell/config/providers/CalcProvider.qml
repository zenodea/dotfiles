pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    readonly property string id: "calc"
    readonly property string label: "Calculator"
    readonly property string tag: "Calculator"
    readonly property string prefix: "="
    readonly property string verb: "Copy result"
    readonly property bool live: true
    readonly property bool fleeting: true
    readonly property bool enabled: Tools.has("qalc")
    readonly property string glyph: "\u{f00ec}"

    property var answers: []
    property string asked: ""
    property bool wanted: false

    function wants(query: string): bool {
        const q = query.trim();
        if (q.startsWith("="))
            return q.length > 1;
        if (!/\d/.test(q))
            return false;
        return /^[\d\s.,+\-*\/^%()]+$/.test(q) ? /[+\-*\/^%]/.test(q) : /\d.*\s(to|in)\s+\S/.test(q);
    }

    function ask(query: string): void {
        asked = query.trim().replace(/^=\s*/, "");
        wanted = wants(query);
        if (wanted) {
            soon.restart();
            return;
        }
        soon.stop();
        answers = [];
    }

    function activate(item: var): void {
        Quickshell.execDetached(["wl-copy", item.title]);
        Notices.show("Calculator", item.title, glyph);
    }

    Timer {
        id: soon

        interval: 30
        onTriggered: {
            if (work.running)
                return;
            work.expression = root.asked;
            work.running = true;
        }
    }

    Process {
        id: work

        property string expression: ""

        command: ["qalc", "-t", expression]

        stdout: StdioCollector {
            onStreamFinished: {
                if (work.expression !== root.asked) {
                    if (root.wanted)
                        soon.restart();
                    return;
                }
                const result = text.trim().replace(/−/g, "-");
                root.answers = !result || result === work.expression || /error|warning/i.test(result) ? [] : [
                    {
                        kind: "calc",
                        name: "result",
                        title: result,
                        sub: work.expression,
                        card: true
                    }
                ];
            }
        }
    }
}
