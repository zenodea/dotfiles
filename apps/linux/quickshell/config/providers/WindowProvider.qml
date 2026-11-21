pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    readonly property string id: "windows"
    readonly property string label: "Windows"
    readonly property string tag: "Window"
    readonly property bool fleeting: true
    readonly property string glyph: "\u{f05b2}"

    function results(query: string): var {
        const q = query.trim().toLowerCase();
        const matches = text => !q || (text ?? "").toLowerCase().includes(q);
        return ToplevelManager.toplevels.values.filter(t => matches(t.title) || matches(t.appId)).map(t => {
            const app = DesktopEntries.heuristicLookup(t.appId);
            return {
                kind: "window",
                name: `${t.appId}:${t.title}`,
                title: t.title || t.appId,
                sub: app?.name ?? t.appId,
                image: Quickshell.iconPath(app?.icon ?? "", true),
                toplevel: t
            };
        });
    }

    function activate(item: var): void {
        item.toplevel.activate();
    }

    function actions(item: var): var {
        return [
            {
                label: "Focus",
                run: () => item.toplevel.activate()
            },
            {
                label: "Close",
                run: () => item.toplevel.close()
            }
        ];
    }
}
