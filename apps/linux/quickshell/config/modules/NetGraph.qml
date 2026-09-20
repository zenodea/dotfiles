import QtQuick
import Quickshell
import qs.style
import qs.services
import qs.widgets

Rectangle {
    id: root

    property ShellScreen screen: null

    readonly property real naturalWidth: row.implicitWidth + Metrics.itemPadding * 2

    implicitWidth: NetSpeed.connected ? naturalWidth : 0
    implicitHeight: Metrics.barHeight
    opacity: NetSpeed.connected ? 1 : 0
    visible: implicitWidth > 0
    clip: true

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
    radius: Metrics.radius
    color: "transparent"

    Row {
        id: row

        anchors.centerIn: parent
        spacing: Metrics.gap

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: NetSpeed.rx
            color: Theme.blue
            font.family: Metrics.iconFont
            font.pixelSize: 9
            font.letterSpacing: -3
            renderType: Text.NativeRendering
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: NetSpeed.tx
            color: Theme.red
            font.family: Metrics.iconFont
            font.pixelSize: 9
            font.letterSpacing: -3
            renderType: Text.NativeRendering
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        onEntered: Popouts.show(root, root.screen, {
                title: `↓ ${NetSpeed.down}   ↑ ${NetSpeed.up}`,
                detail: NetSpeed.iface
            })
    }
}
