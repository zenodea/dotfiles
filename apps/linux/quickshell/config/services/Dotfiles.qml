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

    function apply(kind: string, name: string): void {
        const flag = kind === "theme" ? "--theme" : kind === "font" ? "--font" : "--wallpaper";
        Quickshell.execDetached(["dotfiles", flag, name]);
    }

    function wallpaperPath(name: string): string {
        return root.repo ? `file://${root.repo}/wallpapers/${name}` : "";
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
        command: ["dotfiles", "--fonts-plain"]

        stdout: StdioCollector {
            onStreamFinished: root.fonts = text.trim().split("\n").filter(l => l)
        }
    }

    Process {
        running: true
        command: ["dotfiles", "--wallpapers-plain"]

        stdout: StdioCollector {
            onStreamFinished: root.wallpapers = text.trim().split("\n").filter(l => l)
        }
    }

    FileView {
        path: root.repo ? `${root.repo}/.current-theme` : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.currentTheme = text().trim()
    }

    FileView {
        path: root.repo ? `${root.repo}/.current-font` : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.currentFont = text().trim()
    }
}
