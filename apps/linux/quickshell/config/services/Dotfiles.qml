pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string repo: ""

    property var themes: []
    property var fonts: []
    property var wallpapers: []
    property string currentTheme: ""
    property string currentFont: ""
    property string currentWallpaper: ""
    property bool autoTheme: false
    property bool settled: false

    readonly property bool light: currentTheme.endsWith("-light")
    readonly property string otherVariant: light ? currentTheme.slice(0, -6) : `${currentTheme}-light`
    readonly property bool paired: themes.some(t => t.name === otherVariant)

    function apply(kind: string, name: string): void {
        const flag = kind === "theme" ? "--theme" : kind === "font" ? "--font" : "--wallpaper";
        Quickshell.execDetached([`${root.repo}/bin/dotfiles`, flag, name]);
    }

    function toggleAppearance(): void {
        if (paired)
            apply("theme", otherVariant);
    }

    function randomTheme(): void {
        Quickshell.execDetached([`${root.repo}/bin/dotfiles`, "--random"]);
    }

    function randomWallpaper(): void {
        Quickshell.execDetached([`${root.repo}/bin/dotfiles`, "--wallpaper", "random"]);
    }

    function toggleAuto(): void {
        Quickshell.execDetached([`${root.repo}/bin/dotfiles`, "--auto", autoTheme ? "off" : "on"]);
        autoSoon.restart();
    }

    function checkAuto(): void {
        autoProbe.running = true;
    }

    function wallpaperPath(name: string): string {
        return root.repo ? `file://${root.repo}/wallpapers/full-size/${name}` : "";
    }

    function refreshWallpapers(): void {
        walls.running = true;
    }

    Process {
        running: true
        command: ["sh", "-c", `cd -P '${Quickshell.shellDir}' && cd ../../../.. && pwd`]

        stdout: StdioCollector {
            onStreamFinished: root.repo = text.trim()
        }
    }

    Process {
        running: true
        command: ["bash", `${Quickshell.shellDir}/scripts/themes.sh`]

        stdout: StdioCollector {
            onStreamFinished: root.themes = JSON.parse(text)
        }
    }

    Process {
        running: true
        command: ["bash", `${Quickshell.shellDir}/scripts/fonts.sh`]

        stdout: StdioCollector {
            onStreamFinished: root.fonts = JSON.parse(text)
        }
    }

    Process {
        id: walls

        running: true
        command: ["bash", `${Quickshell.shellDir}/scripts/wallpapers.sh`]

        stdout: StdioCollector {
            onStreamFinished: {
                const found = text.split("\n").filter(line => line.includes("\t")).map(line => {
                    const tab = line.indexOf("\t");
                    const name = line.slice(0, tab);
                    return {
                        name,
                        label: name.replace(/\.[^.]+$/, "").replace(/^\d+[-_ ]*/, "").replace(/[-_]+/g, " "),
                        thumb: `file://${line.slice(tab + 1)}`
                    };
                });
                if (JSON.stringify(found) !== JSON.stringify(root.wallpapers))
                    root.wallpapers = found;
            }
        }
    }

    Process {
        id: autoProbe

        command: ["sh", "-c", `test -f '${root.repo}/.auto-theme' && echo on || echo off`]

        stdout: StdioCollector {
            onStreamFinished: root.autoTheme = text.trim() === "on"
        }
    }

    Timer {
        running: true
        interval: 2500
        onTriggered: root.settled = true
    }

    Timer {
        id: autoSoon

        interval: 400
        onTriggered: root.checkAuto()
    }

    FileView {
        path: root.repo ? `${root.repo}/.current-theme` : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const name = text().trim();
            if (root.settled && name !== root.currentTheme)
                Notices.show("Theme", name, "󰏘");
            root.currentTheme = name;
            root.checkAuto();
        }
    }

    FileView {
        path: root.repo ? `${root.repo}/.current-font` : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const name = text().trim();
            if (root.settled && name !== root.currentFont)
                Notices.show("Font", name, "󰛖");
            root.currentFont = name;
        }
    }

    FileView {
        path: root.repo ? `${root.repo}/.current-wallpaper` : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.currentWallpaper = text().trim()
    }
}
