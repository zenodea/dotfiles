pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.controls
import qs.drawer
import qs.launcher
import qs.bar
import qs.popouts
import qs.services
import qs.style

PanelWindow {
    id: root

    required property ShellScreen modelData

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
    readonly property bool hasFullscreen: monitor?.activeWorkspace?.lastIpcObject?.hasfullscreen ?? false

    property real hide: hasFullscreen ? 1 : 0

    readonly property real escapeScale: height / 2 / Math.max(1, height / 2 - (Metrics.barHeight + Metrics.innerShadow)) * 1.02

    readonly property real innerLeft: Metrics.strip
    readonly property real innerRight: width - Metrics.strip
    readonly property real innerTop: Metrics.barHeight
    readonly property real innerBottom: height - Metrics.strip
    readonly property real innerWidth: innerRight - innerLeft
    readonly property real innerHeight: innerBottom - innerTop

    onHasFullscreenChanged: {
        if (hasFullscreen) {
            Panels.close();
            Popouts.leave();
        }
    }

    Component.onCompleted: Hyprland.refreshWorkspaces()

    Connections {
        function onRawEvent(event: var): void {
            if (["fullscreen", "workspace", "workspacev2", "focusedmon", "openwindow", "closewindow", "movewindowv2"].includes(event.name))
                Hyprland.refreshWorkspaces();
        }

        target: Hyprland
    }

    Behavior on hide {
        NumberAnimation {
            duration: root.hasFullscreen ? Metrics.animDuration : Metrics.escapeDuration
            easing.type: root.hasFullscreen ? Easing.Bezier : Easing.InOutCubic
            easing.bezierCurve: Metrics.easeOutQuint
        }
    }

    screen: modelData
    color: "transparent"
    WlrLayershell.namespace: "dotfiles-shell"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: Panels.anyOpen && Panels.screen?.name === modelData?.name ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    mask: Region {
        item: root.hide > 0.5 ? null : silhouette.bar

        regions: [
            Region {
                item: popout.hitArea
            },
            Region {
                item: leftEdge
            },
            Region {
                item: bottomEdge
            },
            Region {
                item: rightEdge
            },
            Region {
                item: drawer.hitArea
            },
            Region {
                item: controls.hitArea
            },
            Region {
                item: launcher.hitArea
            },
            Region {
                item: toast.hitArea
            }
        ]
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered)
                Popouts.stay();
            else
                Popouts.leave();
        }
    }

    Item {
        anchors.fill: parent
        visible: root.hide < 1

        transform: Scale {
            origin.x: root.width / 2
            origin.y: root.height / 2
            xScale: 1 + (root.escapeScale - 1) * root.hide
            yScale: xScale
        }

        Shade {
            x: root.innerLeft
            y: root.innerTop
            span: root.innerWidth
        }

        Shade {
            x: root.innerRight
            y: root.innerTop
            span: root.innerHeight
            rotation: 90
        }

        Shade {
            x: root.innerRight
            y: root.innerBottom
            span: root.innerWidth
            rotation: 180
        }

        Shade {
            x: root.innerLeft
            y: root.innerBottom
            span: root.innerHeight
            rotation: 270
        }

        Silhouette {
            id: silhouette

            anchors.fill: parent
            frame: root
            workspaces: workspaces
            popout: popout
            drawer: drawer
            controls: controls
            launcher: launcher
            levels: levels
            toast: toast
        }

        Workspaces {
            id: workspaces

            anchors.left: parent.left
            anchors.leftMargin: root.innerLeft
            height: Metrics.barHeight
            screen: root.modelData
        }

        Now {
            anchors.horizontalCenter: parent.horizontalCenter
            height: Metrics.barHeight
            screen: root.modelData
        }

        StatusRow {
            anchors.right: parent.right
            anchors.rightMargin: Metrics.strip
            screen: root.modelData
        }

        Popout {
            id: popout

            screen: root.modelData
            maxX: root.width
        }

        LevelPanel {
            id: levels
        }

        NotificationToast {
            id: toast
        }

        Drawer {
            id: drawer

            screen: root.modelData
        }

        Controls {
            id: controls

            screen: root.modelData
        }

        Launcher {
            id: launcher

            screen: root.modelData
        }

        Item {
            anchors.fill: parent
            focus: (Panels.drawer || Panels.controls) && Panels.launcher === ""
            Keys.onEscapePressed: Panels.close()
        }

        EdgeZone {
            id: leftEdge

            y: root.innerTop
            width: Metrics.strip
            height: root.innerHeight
            onHoveredChanged: Panels.drawerEdgePointer = hovered
            onDwelled: Panels.hoverOpenDrawer()
        }

        EdgeZone {
            id: rightEdge

            x: root.innerRight
            y: root.innerTop
            width: Metrics.strip
            height: root.innerHeight
            onHoveredChanged: Panels.controlsEdgePointer = hovered
            onDwelled: Panels.hoverOpenControls()
        }

        EdgeZone {
            id: bottomEdge

            x: root.innerLeft
            y: root.innerBottom
            width: root.innerWidth
            height: Metrics.strip
            onHoveredChanged: Panels.launcherEdgePointer = hovered
            onDwelled: Panels.hoverOpenLauncher()
        }
    }
}
