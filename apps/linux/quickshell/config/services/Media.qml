pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Singleton {
    id: root

    property string chosen: ""

    readonly property var players: Mpris.players.values.filter(p => !(p.dbusName ?? "").includes("playerctld"))
    readonly property bool many: players.length > 1

    readonly property MprisPlayer player: {
        const pinned = players.find(p => root.key(p) === chosen);
        if (pinned)
            return pinned;
        return players.find(p => p.isPlaying) ?? players[0] ?? null;
    }

    function key(player: var): string {
        return player?.dbusName ?? "";
    }

    function label(player: var): string {
        return player?.identity || player?.desktopEntry || player?.dbusName || "Player";
    }

    function icon(player: var): string {
        const entry = player?.desktopEntry ? DesktopEntries.heuristicLookup(player.desktopEntry) : null;
        return entry?.icon ? Quickshell.iconPath(entry.icon, true) : "";
    }

    function select(player: var): void {
        root.chosen = root.key(player);
    }

    function cycle(): void {
        if (players.length < 2)
            return;
        const at = players.findIndex(p => root.key(p) === root.key(root.player));
        root.chosen = root.key(players[(at + 1) % players.length]);
    }
}
