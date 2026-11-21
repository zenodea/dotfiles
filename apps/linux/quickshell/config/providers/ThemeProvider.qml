pragma Singleton

import QtQuick
import Quickshell
import qs.services

Singleton {
    readonly property string id: "themes"
    readonly property string label: "Themes"
    readonly property string tag: "Theme"
    readonly property string verb: "Apply"
    readonly property int weight: -10
    readonly property string glyph: "\u{f03d8}"

    function titled(name: string): string {
        return name.split("-").map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ");
    }

    function results(query: string): var {
        const q = query.trim().toLowerCase();
        return Dotfiles.themes.filter(t => !q || t.name.toLowerCase().includes(q)).map(t => {
            const light = t.name.endsWith("-light");
            return {
                kind: "theme",
                name: t.name,
                title: titled(t.name),
                swatch: t.bg && t.accent ? [t.bg, t.accent] : null,
                base: light ? t.name.slice(0, -6) : t.name,
                label: titled(light ? t.name.slice(0, -6) : t.name),
                light,
                theme: t,
                current: t.name === Dotfiles.currentTheme
            };
        });
    }

    function activate(item: var): void {
        Dotfiles.apply("theme", item.name);
    }
}
