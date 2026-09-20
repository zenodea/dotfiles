pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.style

Scope {
    id: root

    required property ShellScreen screen

    ExclusionZone {
        anchors.top: true
        exclusiveZone: Metrics.barHeight
    }

    ExclusionZone {
        anchors.left: true
        exclusiveZone: Metrics.strip
    }

    ExclusionZone {
        anchors.right: true
        exclusiveZone: Metrics.strip
    }

    ExclusionZone {
        anchors.bottom: true
        exclusiveZone: Metrics.strip
    }

    component ExclusionZone: PanelWindow {
        screen: root.screen
        color: "transparent"
        mask: Region {}
        implicitWidth: 1
        implicitHeight: 1
        WlrLayershell.namespace: "dotfiles-exclusion"
    }
}
