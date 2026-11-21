pragma Singleton

import QtQuick
import Quickshell
import qs.services

Singleton {
    id: root

    readonly property string id: "session"
    readonly property string label: "Session"
    readonly property string tag: "Session"
    readonly property string verb: "Run"

    readonly property var entries: [
        {
            name: "Lock",
            icon: "󰌾",
            sub: "Keep everything running",
            tone: "calm",
            command: ["qs", "ipc", "call", "shell", "lock"]
        },
        {
            name: "Suspend",
            icon: "󰤄",
            sub: "Sleep to memory",
            tone: "calm",
            command: ["systemctl", "suspend"]
        },
        {
            name: "Hibernate",
            icon: "󰋊",
            sub: "Sleep to disk",
            tone: "calm",
            command: ["systemctl", "hibernate"]
        },
        {
            name: "Logout",
            icon: "󰍃",
            sub: "End this session",
            tone: "warn",
            command: ["hyprctl", "dispatch", "exit"],
            leave: true
        },
        {
            name: "Reboot",
            icon: "󰑓",
            sub: "Restart now",
            tone: "warn",
            command: ["systemctl", "reboot"],
            leave: true
        },
        {
            name: "Shutdown",
            icon: "󰐥",
            sub: "Power off",
            tone: "danger",
            command: ["systemctl", "poweroff"],
            leave: true
        }
    ]

    function results(query: string): var {
        const q = query.trim().toLowerCase();
        return entries.filter(s => !q || s.name.toLowerCase().includes(q)).map(s => Object.assign({
                kind: "session"
            }, s));
    }

    function activate(item: var): void {
        if (item.leave)
            Session.leave(item.command);
        else
            Quickshell.execDetached(item.command);
    }
}
