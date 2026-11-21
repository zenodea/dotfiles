pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property string id: "apps"
    readonly property string label: "Apps"
    readonly property string tag: "Application"
    readonly property int cap: 60
    readonly property bool pictures: true
    readonly property string glyph: "\u{f003b}"

    function results(query: string): var {
        const q = query.trim().toLowerCase();
        const matches = name => !q || name.toLowerCase().includes(q);
        return DesktopEntries.applications.values.filter(a => !a.noDisplay && (matches(a.name) || matches(a.comment ?? ""))).map(a => ({
                    kind: "app",
                    name: a.name,
                    sub: a.genericName || a.comment || "",
                    icon: Quickshell.iconPath(a.icon, true),
                    entry: a
                })).sort((a, b) => (a.icon === "") - (b.icon === "") || a.name.localeCompare(b.name));
    }

    function activate(item: var): void {
        item.entry.execute();
    }

    function actions(item: var): var {
        return [
            {
                label: "Open",
                run: () => item.entry.execute()
            }
        ].concat(item.entry.actions.map(a => ({
                    label: a.name,
                    run: () => a.execute()
                })));
    }
}
