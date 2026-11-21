pragma Singleton

import QtQuick
import Quickshell
import qs.services

Singleton {
    id: root

    readonly property string id: "media"
    readonly property string label: "Media"
    readonly property string tag: "Media"
    readonly property bool fleeting: true
    readonly property string glyph: "\u{f075a}"
    readonly property var player: Media.player

    readonly property var entries: {
        if (!player)
            return [];
        const track = [player.trackTitle, player.trackArtist].filter(Boolean).join(" · ") || Media.label(player);
        const words = "media music song track player";
        return [
            {
                name: "playpause",
                title: player.isPlaying ? "Pause" : "Play",
                sub: track,
                keywords: `${words} play pause toggle`,
                icon: player.isPlaying ? "\u{f03e4}" : "\u{f040a}",
                hidden: !player.canTogglePlaying,
                run: () => root.player.togglePlaying()
            },
            {
                name: "next",
                title: "Next track",
                sub: track,
                keywords: `${words} skip forward`,
                icon: "\u{f04ad}",
                hidden: !player.canGoNext,
                run: () => root.player.next()
            },
            {
                name: "previous",
                title: "Previous track",
                sub: track,
                keywords: `${words} back`,
                icon: "\u{f04ae}",
                hidden: !player.canGoPrevious,
                run: () => root.player.previous()
            }
        ].filter(e => !e.hidden).map(e => Object.assign({
                kind: "media"
            }, e));
    }

    function results(query: string): var {
        const q = query.trim().toLowerCase();
        return entries.filter(e => !q || e.title.toLowerCase().includes(q));
    }

    function activate(item: var): void {
        item.run();
    }

    function actions(item: var): var {
        return [
            {
                label: item.title,
                stay: true,
                run: item.run
            }
        ];
    }
}
