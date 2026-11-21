pragma Singleton

import QtQuick
import Quickshell
import qs.services

Singleton {
    id: root

    readonly property string id: "commands"
    readonly property string label: "Commands"
    readonly property string tag: "Command"
    readonly property string verb: "Run"
    readonly property string glyph: "\u{f018d}"

    readonly property var entries: [
        {
            name: "Keep awake",
            sub: "Stop the screen from sleeping",
            keywords: "caffeinate caffeine coffee idle sleep inhibit",
            icon: Idle.inhibited ? "\u{f0176}" : "\u{f0faa}",
            on: Idle.inhibited,
            hidden: !Idle.available,
            stay: true,
            run: () => Idle.toggle()
        },
        {
            name: "Do not disturb",
            sub: "Hold back notifications",
            keywords: "dnd silence quiet mute notifications",
            icon: Notifs.dnd ? "\u{f009b}" : "\u{f009a}",
            on: Notifs.dnd,
            stay: true,
            run: () => Notifs.dnd = !Notifs.dnd
        },
        {
            name: "Night light",
            sub: "Warm the screen colours",
            keywords: "toggle night mode warm blue",
            icon: Night.on ? "\u{f0594}" : "\u{f0599}",
            on: Night.on,
            hidden: !Night.available,
            stay: true,
            run: () => Night.toggle()
        },
        {
            name: "Zen mode",
            sub: "Hide the bar and frame",
            keywords: "toggle focus fullscreen",
            icon: "\u{f0293}",
            on: Panels.hidden,
            run: () => Panels.toggleZen()
        },
        {
            name: "Automatic theme",
            sub: "Follow the time of day",
            keywords: "toggle auto light dark",
            icon: "\u{f050e}",
            on: Dotfiles.autoTheme,
            stay: true,
            run: () => Dotfiles.toggleAuto()
        },
        {
            name: "Light and dark",
            sub: "Switch to the other variant",
            keywords: "toggle appearance theme",
            icon: Dotfiles.light ? "\u{f05a8}" : "\u{f0594}",
            state: Dotfiles.light ? "Light" : "Dark",
            hidden: !Dotfiles.paired,
            run: () => Dotfiles.toggleAppearance()
        },
        {
            name: "Record screen",
            sub: "Save to Videos",
            icon: "\u{f044a}",
            on: Recorder.recording,
            run: () => Recorder.toggle(false)
        },
        {
            name: "Record region",
            sub: "Save to Videos",
            icon: "\u{f0ec2}",
            on: Recorder.recording,
            run: () => Recorder.toggle(true)
        },
        {
            name: "Browse themes",
            icon: "\u{f03d8}",
            hidden: Panels.hidden,
            run: () => Panels.openLauncher("themes")
        },
        {
            name: "Browse fonts",
            icon: "\u{f06d6}",
            hidden: Panels.hidden,
            run: () => Panels.openLauncher("fonts")
        },
        {
            name: "Browse wallpapers",
            icon: "\u{f0e09}",
            hidden: Panels.hidden,
            run: () => Panels.openLauncher("wallpapers")
        },
        {
            name: "Random theme",
            icon: "\u{f049d}",
            run: () => Dotfiles.randomTheme()
        },
        {
            name: "Random wallpaper",
            icon: "\u{f049d}",
            run: () => Dotfiles.randomWallpaper()
        },
        {
            name: "Screenshot region",
            sub: "Save to Pictures",
            icon: "\u{f0e51}",
            run: () => Screenshot.take("region")
        },
        {
            name: "Screenshot region to clipboard",
            icon: "\u{f018f}",
            run: () => Screenshot.take("clip")
        },
        {
            name: "Screenshot screen",
            sub: "Save to Pictures",
            icon: "\u{f0379}",
            run: () => Screenshot.take("screen")
        }
    ]

    function results(query: string): var {
        const q = query.trim().toLowerCase();
        return entries.filter(c => !c.hidden && (!q || c.name.toLowerCase().includes(q))).map(c => Object.assign({
                kind: "command",
                tag: c.state ?? (c.on === undefined ? root.tag : c.on ? "On" : "Off")
            }, c));
    }

    function activate(item: var): void {
        item.run();
    }

    function actions(item: var): var {
        return [
            {
                label: item.on === undefined ? root.verb : item.on ? "Turn off" : "Turn on",
                stay: item.stay === true,
                run: item.run
            }
        ];
    }
}
