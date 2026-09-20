pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.drawer
import qs.launcher
import qs.modules
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

    readonly property real innerLeft: Metrics.strip
    readonly property real innerRight: width - Metrics.strip
    readonly property real innerTop: Metrics.barHeight
    readonly property real innerBottom: height - Metrics.strip

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
        item: root.hide > 0.5 ? null : bar

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
                item: drawer.hitArea
            },
            Region {
                item: launcher.hitArea
            },
            Region {
                item: toast.hitArea
            }
        ]
    }

    Timer {
        id: leftDwell

        interval: 180
        onTriggered: Panels.hoverOpenDrawer()
    }

    Timer {
        id: bottomDwell

        interval: 180
        onTriggered: Panels.hoverOpenLauncher()
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
            yScale: 1 + (root.escapeScale - 1) * root.hide
        }

        Shade {
            x: root.innerLeft
            y: root.innerTop
            span: root.innerRight - root.innerLeft
        }

        Shade {
            x: root.innerRight
            y: root.innerTop
            span: root.innerBottom - root.innerTop
            rotation: 90
        }

        Shade {
            x: root.innerRight
            y: root.innerBottom
            span: root.innerRight - root.innerLeft
            rotation: 180
        }

        Shade {
            x: root.innerLeft
            y: root.innerBottom
            span: root.innerBottom - root.innerTop
            rotation: 270
        }

        Item {
            anchors.fill: parent

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

                x: workspaces.x + workspaces.tabX
                y: root.innerTop - Metrics.seamOverlap
                width: workspaces.tabWidth
                height: Metrics.workspaceTab + Metrics.seamOverlap
                color: Theme.bg

                Behavior on x {
                    NumberAnimation {
                        duration: Metrics.animDuration
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Metrics.easeOutQuint
                    }
                }
            }

            Fillet {
                size: Metrics.workspaceTab
                x: workspaceTab.x - Metrics.workspaceTab
                y: root.innerTop
                rotation: 90
            }

            Fillet {
                size: Metrics.workspaceTab
                x: workspaceTab.x + workspaceTab.width
                y: root.innerTop
            }

            Rectangle {
                y: root.innerTop
                width: Metrics.strip
                height: root.innerBottom - root.innerTop
                color: Theme.bg
            }

            Rectangle {
                x: root.innerRight
                y: root.innerTop
                width: Metrics.strip
                height: root.innerBottom - root.innerTop
                color: Theme.bg
            }

            Rectangle {
                y: root.innerBottom
                width: parent.width
                height: Metrics.strip
                color: Theme.bg
            }

            Fillet {
                x: root.innerLeft
                y: root.innerTop
            }

            Fillet {
                x: root.innerRight - Metrics.frameRadius
                y: root.innerTop
                rotation: 90
            }

            Fillet {
                x: root.innerRight - Metrics.frameRadius
                y: root.innerBottom - Metrics.frameRadius
                rotation: 180
            }

            Fillet {
                x: root.innerLeft
                y: root.innerBottom - Metrics.frameRadius
                rotation: 270
            }

            Rectangle {
                x: popout.x
                y: popout.y - Metrics.seamOverlap
                width: popout.width
                height: popout.height + Metrics.seamOverlap
                color: Theme.bg
                bottomLeftRadius: popout.x > 0 ? Metrics.frameRadius : 0
                bottomRightRadius: popout.x + popout.width < parent.width ? Metrics.frameRadius : 0
            }

            Rectangle {
                x: drawer.x
                y: drawer.y
                width: drawer.width
                height: drawer.height
                color: Theme.bg
            }

            Rectangle {
                x: launcher.x
                y: launcher.y
                width: launcher.width
                height: launcher.height
                color: Theme.bg
            }

            Rectangle {
                x: levels.x
                y: levels.y - Metrics.seamOverlap
                width: levels.width
                height: levels.height + Metrics.seamOverlap
                color: Theme.bg
                bottomLeftRadius: Metrics.frameRadius
            }

            Rectangle {
                x: toast.x
                y: toast.y - Metrics.seamOverlap
                width: toast.width
                height: toast.height + Metrics.seamOverlap
                color: Theme.bg
                bottomRightRadius: Metrics.frameRadius
            }

            Fillet {
                visible: popout.height > 0 && popout.x > 0
                x: popout.x - Metrics.frameRadius
                y: popout.y
                rotation: 90
            }

            Fillet {
                visible: popout.height > 0 && popout.x + popout.width < parent.width
                x: popout.x + popout.width
                y: popout.y
            }

            Fillet {
                visible: drawer.width > 0
                x: drawer.width
                y: root.innerTop
            }

            Fillet {
                visible: drawer.width > 0
                x: drawer.width
                y: root.innerBottom - Metrics.frameRadius
                rotation: 270
            }

            Fillet {
                visible: launcher.height > 0
                x: root.innerLeft
                y: launcher.y - Metrics.frameRadius
                rotation: 270
            }

            Fillet {
                visible: launcher.height > 0
                x: root.innerRight - Metrics.frameRadius
                y: launcher.y - Metrics.frameRadius
                rotation: 180
            }

            Fillet {
                visible: toast.width > 0
                x: toast.width
                y: toast.y
            }

            Fillet {
                visible: toast.width > 0
                x: root.innerLeft
                y: toast.y + toast.height
            }

            Fillet {
                visible: levels.width > 0
                x: levels.x - Metrics.frameRadius
                y: levels.y
                rotation: 90
            }

            Fillet {
                visible: levels.width > 0
                x: root.innerRight - Metrics.frameRadius
                y: levels.y + levels.height
                rotation: 90
            }
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

        Row {
            anchors.right: parent.right
            anchors.rightMargin: root.innerLeft
            height: Metrics.barHeight
            spacing: 0

            CapsLock {
                screen: root.modelData
            }

            Mic {
                screen: root.modelData
            }

            Volume {
                screen: root.modelData
            }

            Backlight {
                screen: root.modelData
            }

            Performance {
                screen: root.modelData
            }

            Mullvad {
                screen: root.modelData
            }

            NetworkStatus {
                screen: root.modelData
            }

            BluetoothStatus {
                screen: root.modelData
            }

            NetGraph {
                screen: root.modelData
            }

            Battery {
                screen: root.modelData
            }
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

        Launcher {
            id: launcher

            screen: root.modelData
        }

        Item {
            id: keyboard

            anchors.fill: parent
            focus: Panels.drawer && Panels.launcher === ""
            Keys.onEscapePressed: Panels.close()
        }

        Item {
            id: leftEdge

            y: root.innerTop
            width: Metrics.strip
            height: root.innerBottom - root.innerTop

            HoverHandler {
                onHoveredChanged: {
                    Panels.drawerEdgePointer = hovered;
                    if (hovered)
                        leftDwell.restart();
                    else
                        leftDwell.stop();
                }
            }
        }

        Item {
            id: bottomEdge

            x: root.innerLeft
            y: root.innerBottom
            width: root.innerRight - root.innerLeft
            height: Metrics.strip

            HoverHandler {
                onHoveredChanged: {
                    Panels.launcherEdgePointer = hovered;
                    if (hovered)
                        bottomDwell.restart();
                    else
                        bottomDwell.stop();
                }
            }
        }
    }
}
