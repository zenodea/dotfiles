pragma Singleton

import QtQuick
import Quickshell
import qs.services

Singleton {
    readonly property string id: "fonts"
    readonly property string label: "Fonts"
    readonly property string tag: "Font"
    readonly property string verb: "Apply"
    readonly property int weight: -10
    readonly property string glyph: "\u{f06d6}"

    function titled(name: string): string {
        return name.split("-").map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ");
    }

    function results(query: string): var {
        const q = query.trim().toLowerCase();
        const matches = name => !q || (name ?? "").toLowerCase().includes(q);
        const active = Dotfiles.fonts.find(f => f.name === Dotfiles.currentFont);
        const mono = Dotfiles.fonts.filter(f => matches(f.name) || matches(f.mono)).map(f => ({
                    kind: "font",
                    name: f.name,
                    label: f.title ?? titled(f.name),
                    face: f.installed === false ? "" : f.mono ?? "",
                    font: f,
                    current: f.name === Dotfiles.currentFont
                }));
        const text = Dotfiles.textFonts.filter(f => matches(f.name) || matches(f.family)).map(f => ({
                    kind: "text-font",
                    name: f.name,
                    label: f.title ?? titled(f.name),
                    tag: "Text font",
                    face: f.installed === false ? "" : f.family ?? "",
                    font: f,
                    current: Dotfiles.currentTextFont ? f.name === Dotfiles.currentTextFont : f.family === active?.text
                }));
        const rows = [];
        for (let i = 0; i < Math.max(mono.length, text.length); i++)
            rows.push(mono[i] ?? {
                kind: "blank"
            }, text[i] ?? {
                kind: "blank"
            });
        return rows;
    }

    function activate(item: var): void {
        Dotfiles.apply(item.kind, item.name);
    }
}
