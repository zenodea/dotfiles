pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property string id: "web"
    readonly property string label: "Web"
    readonly property string tag: "Web"
    readonly property string verb: "Open in browser"
    readonly property bool live: true
    readonly property bool last: true
    readonly property bool fleeting: true
    readonly property string glyph: "\u{f059f}"
    readonly property string engine: "https://duckduckgo.com/?q="

    property var answers: []

    function ask(query: string): void {
        const q = query.trim();
        if (q.length < 2) {
            answers = [];
            return;
        }
        const address = /^https?:\/\/\S+$/i.test(q) || /^[^\s\/]+\.[a-z]{2,}(\/\S*)?$/i.test(q);
        answers = (address ? [
                {
                    kind: "web",
                    name: "open",
                    title: `Open ${q}`,
                    url: /^https?:\/\//i.test(q) ? q : `https://${q}`
                }
            ] : []).concat([
            {
                kind: "web",
                name: "search",
                title: `Search the web for "${q}"`,
                url: engine + encodeURIComponent(q)
            }
        ]);
    }

    function activate(item: var): void {
        Quickshell.execDetached(["xdg-open", item.url]);
    }
}
