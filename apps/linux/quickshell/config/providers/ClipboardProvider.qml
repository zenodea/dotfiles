pragma Singleton

import QtQuick
import Quickshell
import qs.services

Singleton {
    readonly property string id: "clipboard"
    readonly property string label: "Clipboard"
    readonly property string hint: "Search what you copied"
    readonly property string prefix: ";"
    readonly property string tag: "Text"
    readonly property bool scoped: true
    readonly property bool fleeting: true
    readonly property bool enabled: ClipboardHistory.available
    readonly property string glyph: "\u{f014d}"

    function results(query: string): var {
        const q = query.trim().toLowerCase();
        return ClipboardHistory.entries.filter(e => !q || e.preview.toLowerCase().includes(q)).map(e => ({
                    kind: "clip",
                    name: e.id,
                    title: e.kind === "image" ? `Image (${e.preview})` : e.preview,
                    image: e.kind === "image" ? ClipboardHistory.path(e.id) : "",
                    tag: e.kind === "image" ? "Image" : "Text"
                }));
    }

    function activate(item: var): void {
        actions(item)[0].run();
    }

    function actions(item: var): var {
        const paste = Tools.has("wtype") ? [
            {
                label: "Paste",
                run: () => {
                    ClipboardHistory.copy(item.name);
                    Quickshell.execDetached(["sh", "-c", "sleep 0.2; wtype -M ctrl v -m ctrl"]);
                }
            }
        ] : [];
        return paste.concat([
            {
                label: "Copy",
                run: () => ClipboardHistory.copy(item.name)
            },
            {
                label: "Delete",
                stay: true,
                run: () => ClipboardHistory.forget(item.name)
            }
        ]);
    }
}
