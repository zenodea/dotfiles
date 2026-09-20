pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.style

Item {
    id: root

    required property ShellScreen screen

    readonly property var icons: ["⼀", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property int activeId: monitor?.activeWorkspace?.id ?? 1
    readonly property int itemWidth: 30

    function occupied(id: int): bool {
        const ws = Hyprland.workspaces.values.find(w => w.id === id);
        return (ws?.lastIpcObject?.windows ?? 0) > 0;
    }

    implicitWidth: row.implicitWidth
    implicitHeight: Metrics.barHeight

    Rectangle {
        id: marker

        x: (root.activeId - 1) * root.itemWidth
        y: parent.height - Metrics.borderWidth * 3
        width: root.itemWidth
        height: Metrics.borderWidth * 2
        color: Theme.accent

        Behavior on x {
            NumberAnimation {
                duration: Metrics.animDuration
                easing.type: Easing.Bezier
                easing.bezierCurve: Metrics.easeOutQuint
            }
        }
    }

    Row {
        id: row

        spacing: 0

        Repeater {
            model: 10

            Rectangle {
                id: ws

                required property int index

                readonly property int id: index + 1
                readonly property bool isActive: root.activeId === id
                readonly property bool isOccupied: root.occupied(id)

                width: root.itemWidth
                height: Metrics.barHeight
                radius: Metrics.radius
                color: isActive ? Theme.alpha(Theme.accent, 0.15) : "transparent"

                Behavior on color {
                    ColorAnimation {
                        duration: Metrics.shortAnim
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.icons[ws.index]
                    color: ws.isActive || area.containsMouse ? Theme.accent : ws.isOccupied ? Theme.fg : Theme.alpha(Theme.muted, 0.55)
                    font.family: Theme.fontMono
                    font.pixelSize: 14
                    renderType: Text.NativeRendering

                    Behavior on color {
                        ColorAnimation {
                            duration: Metrics.animDuration
                        }
                    }
                }

                MouseArea {
                    id: area

                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Hyprland.dispatch(`workspace ${ws.id}`)
                }
            }
        }
    }
}
