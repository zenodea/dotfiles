pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.style

// the frame's solid shape: bar, side strips, rounded corners and the backings behind open panels
Item {
    id: root

    required property var frame
    required property Item workspaces
    required property Item popout
    required property Item drawer
    required property Item controls
    required property Item launcher
    required property Item levels
    required property Item toast

    readonly property alias bar: bar
    readonly property real popoutRadius: Math.min(Metrics.frameRadius, Math.max(0, popout.height) / 2)

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        blurMax: Metrics.shadowBlur
        shadowColor: Qt.rgba(0, 0, 0, Metrics.shadowOpacity)
    }

    Rectangle {
        id: bar

        width: parent.width
        height: Metrics.barHeight
        color: Theme.bg

        Behavior on color {
            ColorAnimation {
                duration: Metrics.animDuration
            }
        }
    }

    Rectangle {
        id: workspaceTab

        x: root.workspaces.x + root.workspaces.tabX
        y: root.frame.innerTop - Metrics.seamOverlap
        width: root.workspaces.tabWidth
        height: Metrics.workspaceTab + Metrics.seamOverlap
        bottomLeftRadius: Metrics.workspaceTab
        bottomRightRadius: Metrics.workspaceTab
        color: Theme.bg

        Behavior on x {
            Ease {}
        }
    }

    Fillet {
        size: Metrics.workspaceTab
        x: workspaceTab.x - Metrics.workspaceTab
        y: root.frame.innerTop
        rotation: 90
    }

    Fillet {
        size: Metrics.workspaceTab
        x: workspaceTab.x + workspaceTab.width
        y: root.frame.innerTop
    }

    Rectangle {
        y: root.frame.innerTop
        width: Metrics.strip
        height: root.frame.innerHeight
        color: Theme.bg
    }

    Rectangle {
        x: root.frame.innerRight
        y: root.frame.innerTop
        width: Metrics.strip
        height: root.frame.innerHeight
        color: Theme.bg
    }

    Rectangle {
        y: root.frame.innerBottom
        width: parent.width
        height: Metrics.strip
        color: Theme.bg
    }

    Fillet {
        x: root.frame.innerLeft
        y: root.frame.innerTop
    }

    Fillet {
        x: root.frame.innerRight - Metrics.frameRadius
        y: root.frame.innerTop
        rotation: 90
    }

    Fillet {
        x: root.frame.innerRight - Metrics.frameRadius
        y: root.frame.innerBottom - Metrics.frameRadius
        rotation: 180
    }

    Fillet {
        x: root.frame.innerLeft
        y: root.frame.innerBottom - Metrics.frameRadius
        rotation: 270
    }

    Backing {
        panel: root.popout
        bottomLeftRadius: root.popout.x > 0 ? root.popoutRadius : 0
        bottomRightRadius: root.popout.x + root.popout.width < parent.width ? root.popoutRadius : 0
    }

    Backing {
        panel: root.drawer
        seam: 0
    }

    Backing {
        panel: root.controls
        seam: 0
    }

    Backing {
        panel: root.launcher
        seam: 0
    }

    Backing {
        panel: root.levels
        bottomLeftRadius: Metrics.frameRadius
    }

    Backing {
        panel: root.toast
        bottomRightRadius: root.toast.radius
    }

    Fillet {
        visible: root.popout.height > 0 && root.popout.x > 0
        size: root.popoutRadius
        x: root.popout.x - root.popoutRadius
        y: root.popout.y
        rotation: 90
    }

    Fillet {
        visible: root.popout.height > 0 && root.popout.x + root.popout.width < parent.width
        size: root.popoutRadius
        x: root.popout.x + root.popout.width
        y: root.popout.y
    }

    Fillet {
        visible: root.drawer.width > 0
        x: root.drawer.width
        y: root.frame.innerTop
    }

    Fillet {
        visible: root.drawer.width > 0
        x: root.drawer.width
        y: root.frame.innerBottom - Metrics.frameRadius
        rotation: 270
    }

    Fillet {
        visible: root.controls.width > 0
        x: root.controls.x - Metrics.frameRadius
        y: root.frame.innerTop
        rotation: 90
    }

    Fillet {
        visible: root.controls.width > 0
        x: root.controls.x - Metrics.frameRadius
        y: root.frame.innerBottom - Metrics.frameRadius
        rotation: 180
    }

    Fillet {
        visible: root.launcher.height > 0
        x: root.frame.innerLeft
        y: root.launcher.y - Metrics.frameRadius
        rotation: 270
    }

    Fillet {
        visible: root.launcher.height > 0
        x: root.frame.innerRight - Metrics.frameRadius
        y: root.launcher.y - Metrics.frameRadius
        rotation: 180
    }

    Fillet {
        visible: root.toast.width > 0
        size: root.toast.radius
        x: root.toast.width
        y: root.toast.y
    }

    Fillet {
        visible: root.toast.width > 0
        size: root.toast.radius
        x: root.frame.innerLeft
        y: root.toast.y + root.toast.height
    }

    Fillet {
        visible: root.levels.width > 0
        x: root.levels.x - Metrics.frameRadius
        y: root.levels.y
        rotation: 90
    }

    Fillet {
        visible: root.levels.width > 0
        x: root.frame.innerRight - Metrics.frameRadius
        y: root.levels.y + root.levels.height
        rotation: 90
    }

    component Backing: Rectangle {
        required property Item panel
        property real seam: Metrics.seamOverlap

        x: panel.x
        y: panel.y - seam
        width: panel.width
        height: panel.height + seam
        color: Theme.bg
    }
}
