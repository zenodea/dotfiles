pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property color bg: "#282828"
    property color surface: "#3c3836"
    property color muted: "#928374"
    property color fg: "#ebdbb2"
    property color fgBright: "#fbf1c7"
    property color accent: "#83a598"
    property color blue: "#458588"
    property color red: "#fb4934"
    property color green: "#b8bb26"
    property color yellow: "#fabd2f"
    property color orange: "#fe8019"
    property color purple: "#d3869b"

    property string monoRequested: "monospace"
    property bool fade: false

    readonly property var monoFallbacks: ["Berkeley Mono", "TX-02", "AtkynsonMono Nerd Font", "Hack", "Adwaita Mono", "Noto Sans Mono"]

    readonly property string fontMono: {
        const installed = Qt.fontFamilies();
        if (monoRequested && installed.includes(monoRequested))
            return monoRequested;
        for (const family of monoFallbacks)
            if (installed.includes(family))
                return family;
        return "monospace";
    }

    function alpha(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    function load(data: string): void {
        let t;
        try {
            t = JSON.parse(data);
        } catch (e) {
            return;
        }

        const c = t.colours;

        root.bg = c.bg;
        root.surface = c.surface;
        root.muted = c.muted;
        root.fg = c.fg;
        root.fgBright = c.fgBright;
        root.accent = c.accent;
        root.blue = c.blue;
        root.red = c.red;
        root.green = c.green;
        root.yellow = c.yellow;
        root.orange = c.orange;
        root.purple = c.purple;

        root.monoRequested = t.font.mono;
    }

    FileView {
        id: file

        path: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/dotfiles/quickshell-theme.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.load(text())
        onLoadFailed: retry.restart()
    }

    Timer {
        id: retry

        interval: 2000
        onTriggered: file.reload()
    }

    Behavior on bg {
        enabled: root.fade

        ColorAnimation {
            duration: Metrics.lockDuration
            easing.type: Easing.InOutCubic
        }
    }

    Behavior on surface {
        enabled: root.fade

        ColorAnimation {
            duration: Metrics.lockDuration
            easing.type: Easing.InOutCubic
        }
    }

    Behavior on muted {
        enabled: root.fade

        ColorAnimation {
            duration: Metrics.lockDuration
            easing.type: Easing.InOutCubic
        }
    }

    Behavior on fg {
        enabled: root.fade

        ColorAnimation {
            duration: Metrics.lockDuration
            easing.type: Easing.InOutCubic
        }
    }

    Behavior on fgBright {
        enabled: root.fade

        ColorAnimation {
            duration: Metrics.lockDuration
            easing.type: Easing.InOutCubic
        }
    }

    Behavior on accent {
        enabled: root.fade

        ColorAnimation {
            duration: Metrics.lockDuration
            easing.type: Easing.InOutCubic
        }
    }

    Behavior on blue {
        enabled: root.fade

        ColorAnimation {
            duration: Metrics.lockDuration
            easing.type: Easing.InOutCubic
        }
    }

    Behavior on red {
        enabled: root.fade

        ColorAnimation {
            duration: Metrics.lockDuration
            easing.type: Easing.InOutCubic
        }
    }

    Behavior on green {
        enabled: root.fade

        ColorAnimation {
            duration: Metrics.lockDuration
            easing.type: Easing.InOutCubic
        }
    }

    Behavior on yellow {
        enabled: root.fade

        ColorAnimation {
            duration: Metrics.lockDuration
            easing.type: Easing.InOutCubic
        }
    }

    Behavior on orange {
        enabled: root.fade

        ColorAnimation {
            duration: Metrics.lockDuration
            easing.type: Easing.InOutCubic
        }
    }

    Behavior on purple {
        enabled: root.fade

        ColorAnimation {
            duration: Metrics.lockDuration
            easing.type: Easing.InOutCubic
        }
    }
}
