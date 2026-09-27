import QtQuick
import Quickshell
import qs.services

// what the launcher lists for each mode, and what activating an entry does
QtObject {
    id: root

    property string mode: "apps"
    property string query: ""

    readonly property var modes: [
        {
            id: "apps",
            label: "Apps"
        },
        {
            id: "themes",
            label: "Themes"
        },
        {
            id: "fonts",
            label: "Fonts"
        },
        {
            id: "wallpapers",
            label: "Wallpapers"
        },
        {
            id: "session",
            label: "Session"
        }
    ]

    readonly property var sessionItems: [
        {
            name: "Lock",
            icon: "󰌾",
            sub: "Keep everything running",
            tone: "calm",
            command: ["hyprlock"]
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
            command: ["hyprctl", "dispatch", "exit"]
        },
        {
            name: "Reboot",
            icon: "󰑓",
            sub: "Restart now",
            tone: "warn",
            command: ["systemctl", "reboot"]
        },
        {
            name: "Shutdown",
            icon: "󰐥",
            sub: "Power off",
            tone: "danger",
            command: ["systemctl", "poweroff"]
        }
    ]

    readonly property var results: {
        const q = query.trim().toLowerCase();
        const matches = name => !q || name.toLowerCase().includes(q);

        if (mode === "apps")
            return DesktopEntries.applications.values.filter(a => !a.noDisplay && (matches(a.name) || matches(a.comment ?? ""))).map(a => ({
                        kind: "app",
                        name: a.name,
                        sub: a.genericName || a.comment || "",
                        icon: Quickshell.iconPath(a.icon, true),
                        entry: a
                    })).sort((a, b) => (a.icon === "") - (b.icon === "") || a.name.localeCompare(b.name)).slice(0, 60);

        if (mode === "themes")
            return Dotfiles.themes.filter(t => matches(t.name)).map(t => {
                const light = t.name.endsWith("-light");
                return {
                    kind: "theme",
                    name: t.name,
                    base: light ? t.name.slice(0, -6) : t.name,
                    label: titled(light ? t.name.slice(0, -6) : t.name),
                    light,
                    theme: t,
                    current: t.name === Dotfiles.currentTheme
                };
            }).sort((a, b) => a.base.localeCompare(b.base) || a.light - b.light);

        if (mode === "fonts") {
            const active = Dotfiles.fonts.find(f => f.name === Dotfiles.currentFont);
            const mono = Dotfiles.fonts.filter(f => matches(f.name) || matches(f.mono)).map(f => ({
                        kind: "font",
                        name: f.name,
                        label: f.title ?? titled(f.name),
                        font: f,
                        current: f.name === Dotfiles.currentFont
                    }));
            const text = Dotfiles.textFonts.filter(f => matches(f.name) || matches(f.family)).map(f => ({
                        kind: "text-font",
                        name: f.name,
                        label: f.title ?? titled(f.name),
                        font: f,
                        current: Dotfiles.currentTextFont ? f.name === Dotfiles.currentTextFont : f.family === active?.text
                    }));
            // interleaved so the grid's two rows are mono on top, text below
            const rows = [];
            for (let i = 0; i < Math.max(mono.length, text.length); i++)
                rows.push(mono[i] ?? {
                    kind: "blank"
                }, text[i] ?? {
                    kind: "blank"
                });
            return rows;
        }

        if (mode === "wallpapers")
            return Dotfiles.wallpapers.filter(w => matches(w.name) || matches(w.label)).map(w => ({
                        kind: "wallpaper",
                        name: w.name,
                        label: w.label,
                        thumb: w.thumb,
                        current: w.name === Dotfiles.currentWallpaper
                    }));

        if (mode === "session")
            return sessionItems.filter(s => matches(s.name)).map(s => Object.assign({
                    kind: "session"
                }, s));

        return [];
    }

    function titled(name: string): string {
        return name.split("-").map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ");
    }

    function nextMode(): string {
        const i = modes.findIndex(m => m.id === mode);
        return modes[(i + 1) % modes.length].id;
    }

    // returns false for entries that do nothing (grid padding)
    function activate(item: var): bool {
        if (!item || item.kind === "blank")
            return false;
        if (item.kind === "app")
            item.entry.execute();
        else if (item.kind === "theme")
            Dotfiles.apply("theme", item.name);
        else if (item.kind === "font")
            Dotfiles.apply("font", item.name);
        else if (item.kind === "text-font")
            Dotfiles.apply("text-font", item.name);
        else if (item.kind === "wallpaper") {
            Dotfiles.apply("wallpaper", item.name);
            Notices.show("Wallpaper", item.label, "󰸉");
        } else if (item.kind === "session")
            Quickshell.execDetached(item.command);
        return true;
    }
}
