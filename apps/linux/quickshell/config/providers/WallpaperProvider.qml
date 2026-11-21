pragma Singleton

import QtQuick
import Quickshell
import qs.services

Singleton {
    readonly property string id: "wallpapers"
    readonly property string label: "Wallpapers"
    readonly property string tag: "Wallpaper"
    readonly property string verb: "Apply"
    readonly property int weight: -50
    readonly property string glyph: "\u{f0e09}"

    function results(query: string): var {
        const q = query.trim().toLowerCase();
        const matches = name => !q || name.toLowerCase().includes(q);
        return Dotfiles.wallpapers.filter(w => matches(w.name) || matches(w.label)).map(w => ({
                    kind: "wallpaper",
                    name: w.name,
                    label: w.label,
                    thumb: w.thumb,
                    image: w.thumb,
                    current: w.name === Dotfiles.currentWallpaper
                }));
    }

    function activate(item: var): void {
        Dotfiles.apply("wallpaper", item.name);
        Notices.show("Wallpaper", item.label, glyph);
    }
}
