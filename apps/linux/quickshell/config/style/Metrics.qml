pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property int borderWidth: 1
    readonly property int radius: 0
    readonly property int frameRadius: 10
    readonly property int seamOverlap: 2
    readonly property int workspaceTab: 4

    readonly property int barHeight: 36
    readonly property int strip: 8

    readonly property int itemPadding: 10
    readonly property int iconSize: 16
    readonly property int fontSize: 13
    readonly property int spacing: 2
    readonly property int sectionSpacing: 12
    readonly property int gap: 6

    readonly property int popoutPadding: 12

    readonly property int shadowBlur: 32
    readonly property real shadowOpacity: 0.9
    readonly property int innerShadow: 36
    readonly property real innerShadowOpacity: 0.2

    readonly property int popoutMinWidth: 120

    readonly property int drawerWidth: 380
    readonly property int drawerPadding: 16
    readonly property int launcherHeight: 300
    readonly property int launcherHeader: 44
    readonly property int launcherFooter: 26
    readonly property int launcherCellWidth: 260
    readonly property int launcherCellHeight: 52

    readonly property var easeOutQuint: [0.23, 1, 0.32, 1, 1, 1]
    readonly property int shortAnim: 150
    readonly property int animDuration: 300

    readonly property var emphasized: [0.38, 1.21, 0.22, 1, 1, 1]
    readonly property int morphDuration: 450
    readonly property int escapeDuration: 420

    readonly property string iconFont: {
        const installed = Qt.fontFamilies();
        const wanted = ["Symbols Nerd Font", "Symbols Nerd Font Mono", "AtkynsonMono Nerd Font", "JetBrainsMono Nerd Font"];
        for (const family of wanted)
            if (installed.includes(family))
                return family;
        return "monospace";
    }
}
