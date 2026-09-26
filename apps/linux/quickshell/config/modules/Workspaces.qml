pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.style

Item {
    id: root

    required property ShellScreen screen

    readonly property var icons: ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property int activeId: monitor?.activeWorkspace?.id ?? 1
    readonly property int itemWidth: 30

    readonly property real tabX: (activeId - 1) * itemWidth
    readonly property real tabWidth: itemWidth

    function occupied(id: int): bool {
        const ws = Hyprland.workspaces.values.find(w => w.id === id);
        return (ws?.lastIpcObject?.windows ?? 0) > 0;
    }

    implicitWidth: row.implicitWidth
    implicitHeight: Metrics.barHeight

    Row {
        id: row

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
                color: "transparent"

                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -1
                    text: root.icons[ws.index]
                    color: ws.isActive || area.containsMouse ? Theme.accent : ws.isOccupied ? Theme.fgBright : Theme.alpha(Theme.muted, 0.45)
                    font.family: Theme.fontMono
                    font.pixelSize: 15
                    font.weight: ws.isActive ? Font.DemiBold : Font.Normal
                    renderType: Text.QtRendering

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
