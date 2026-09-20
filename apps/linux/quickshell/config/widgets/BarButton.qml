pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.style
import qs.services

Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property color iconColour: Theme.fg
    property color labelColour: Theme.fg
    property bool active: false
    property bool hoverable: true
    property bool shown: true

    property real level: -1
    property real labelWidth: 0
    property real iconWidth: Metrics.iconSize + 4

    property ShellScreen screen: null
    property string title: ""
    property string detail: ""
    property Component popoutContent: null

    readonly property var popoutOpts: ({
            title: title,
            detail: detail,
            level: level,
            content: popoutContent
        })

    signal clicked(var mouse)
    signal scrolled(int delta)

    readonly property bool hovered: area.containsMouse
    readonly property bool lit: hovered && hoverable

    onHoveredChanged: {
        if (hovered && (title || popoutContent))
            Popouts.show(root, screen, popoutOpts);
    }

    onPopoutOptsChanged: {
        if (hovered && (title || popoutContent))
            Popouts.show(root, screen, popoutOpts);
    }

    readonly property real naturalWidth: row.implicitWidth + Metrics.itemPadding * 2

    implicitWidth: shown ? naturalWidth : 0
    implicitHeight: Metrics.barHeight
    opacity: shown ? 1 : 0
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
    color: active ? Theme.alpha(Theme.accent, 0.15) : "transparent"

    Behavior on color {
        ColorAnimation {
            duration: Metrics.shortAnim
        }
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: root.label ? Metrics.gap : 0

        transform: Translate {
            y: root.lit ? -1 : 0

            Behavior on y {
                NumberAnimation {
                    duration: Metrics.shortAnim
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Metrics.easeOutQuint
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon !== ""
            width: root.iconWidth > 0 ? root.iconWidth : implicitWidth
            horizontalAlignment: Text.AlignHCenter
            text: root.icon
            color: root.lit ? Theme.accent : root.iconColour
            font.family: Metrics.iconFont
            font.pixelSize: Metrics.iconSize
            renderType: Text.NativeRendering

            Behavior on color {
                ColorAnimation {
                    duration: Metrics.shortAnim
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.label !== ""
            width: root.labelWidth > 0 ? root.labelWidth : implicitWidth
            horizontalAlignment: root.labelWidth > 0 ? Text.AlignRight : Text.AlignLeft
            text: root.label
            color: root.lit ? Theme.accent : root.labelColour
            font.family: Theme.fontMono
            font.pixelSize: Metrics.fontSize
            renderType: Text.NativeRendering

            Behavior on color {
                ColorAnimation {
                    duration: Metrics.shortAnim
                }
            }
        }
    }

    Rectangle {
        visible: root.level >= 0
        x: Metrics.itemPadding
        y: parent.height - 8
        width: parent.width - Metrics.itemPadding * 2
        height: 2
        color: Theme.alpha(Theme.fg, 0.15)

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.level))
            height: parent.height
            color: root.lit ? Theme.accent : Theme.alpha(Theme.accent, 0.7)

            Behavior on width {
                NumberAnimation {
                    duration: Metrics.shortAnim
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Metrics.easeOutQuint
                }
            }
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => root.clicked(mouse)
        onWheel: wheel => root.scrolled(wheel.angleDelta.y)
    }
}
