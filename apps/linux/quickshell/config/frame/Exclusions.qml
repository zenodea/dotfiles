pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.style

Scope {
    id: root

    required property ShellScreen screen

    ExclusionZone {
        anchors.top: true
        exclusiveZone: Panels.hidden ? Metrics.strip : Metrics.barHeight
    }

    ExclusionZone {
        anchors.left: true
    }

    ExclusionZone {
        anchors.right: true
    }

    ExclusionZone {
        anchors.bottom: true
    }

    component ExclusionZone: PanelWindow {
        screen: root.screen
        exclusiveZone: Metrics.strip
        color: "transparent"
        mask: Region {}
        implicitWidth: 1
        implicitHeight: 1
        WlrLayershell.namespace: "dotfiles-exclusion"
    }
}
