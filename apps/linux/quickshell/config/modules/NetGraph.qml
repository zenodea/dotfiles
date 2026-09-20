pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.style

Rectangle {
    id: root

    property ShellScreen screen: null

    readonly property int columns: 40
    readonly property int columnWidth: 2
    readonly property int columnGap: 1
    readonly property int graphWidth: columns * (columnWidth + columnGap) - columnGap
    readonly property int graphHeight: 18
    readonly property real naturalWidth: graphWidth + Metrics.itemPadding * 2

    implicitWidth: NetSpeed.connected ? naturalWidth : 0
    implicitHeight: Metrics.barHeight
    opacity: NetSpeed.connected ? 1 : 0
    visible: implicitWidth > 0
    clip: true
    color: "transparent"

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Metrics.animDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: Metrics.easeOutQuint
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: Metrics.shortAnim
        }
    }

    Item {
        anchors.centerIn: parent
        width: root.graphWidth
        height: root.graphHeight

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: Metrics.borderWidth
            color: Theme.alpha(Theme.fg, 0.18)
        }

        Repeater {
            model: root.columns

            Item {
                id: column

                required property int index

                readonly property real down: NetSpeed.rx[index] ?? 0
                readonly property real up: NetSpeed.tx[index] ?? 0
                readonly property real half: root.graphHeight / 2 - 1

                x: index * (root.columnWidth + root.columnGap)
                width: root.columnWidth
                height: root.graphHeight

                Rectangle {
                    x: 0
                    y: column.half - height
                    width: parent.width
                    height: Math.max(column.down > 0 ? 1 : 0, Math.min(1, column.down) * column.half)
                    color: Theme.blue

                    Behavior on height {
                        NumberAnimation {
                            duration: Metrics.shortAnim
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Metrics.easeOutQuint
                        }
                    }
                }

                Rectangle {
                    x: 0
                    y: column.half + Metrics.borderWidth
                    width: parent.width
                    height: Math.max(column.up > 0 ? 1 : 0, Math.min(1, column.up) * column.half)
                    color: Theme.alpha(Theme.red, 0.85)

                    Behavior on height {
                        NumberAnimation {
                            duration: Metrics.shortAnim
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Metrics.easeOutQuint
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        onEntered: Popouts.show(root, root.screen, {
            title: `↓ ${NetSpeed.down}`,
            detail: `↑ ${NetSpeed.up} · ${NetSpeed.iface}`,
            fixedWidth: root.naturalWidth
        })
    }
}
