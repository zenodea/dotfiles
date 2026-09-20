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
    readonly property bool hasFullscreen: monitor?.activeWorkspace?.toplevels?.values?.some(t => (t.lastIpcObject?.fullscreen ?? 0) > 1) ?? false

    readonly property real innerLeft: Metrics.strip
    readonly property real innerRight: width - Metrics.strip
    readonly property real innerTop: Metrics.barHeight
    readonly property real innerBottom: height - Metrics.strip

    screen: modelData
    color: "transparent"
    WlrLayershell.namespace: "dotfiles-shell"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: Panels.anyOpen && Panels.screen?.name === modelData?.name ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    mask: Region {
        item: bar

        regions: [
            Region {
                item: popout.hitArea
            },
            Region {
                item: rightEdge
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
        id: rightDwell

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
        opacity: root.hasFullscreen ? 0 : 1
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: Metrics.animDuration
                easing.type: Easing.Bezier
                easing.bezierCurve: Metrics.easeOutQuint
            }
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

            Rectangle {
                x: popout.x
                y: popout.y
                width: popout.width
                height: popout.height
                color: Theme.bg
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
                y: levels.y
                width: levels.width
                height: levels.height
                color: Theme.bg
            }

            Rectangle {
                x: toast.x
                y: toast.y
                width: toast.width
                height: toast.height
                color: Theme.bg
            }
        }

        Workspaces {
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
            maxX: root.innerRight
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
            id: rightEdge

            x: root.innerRight
            y: root.innerTop
            width: Metrics.strip
            height: root.innerBottom - root.innerTop

            HoverHandler {
                onHoveredChanged: {
                    Panels.drawerEdgePointer = hovered;
                    if (hovered)
                        rightDwell.restart();
                    else
                        rightDwell.stop();
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
