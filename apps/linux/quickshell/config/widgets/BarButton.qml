pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.style
import qs.services

Item {
    id: root

    property string icon: ""
    property string label: ""
    property color iconColour: Theme.fg
    property color labelColour: Theme.fg
    property bool hoverable: true
    property bool shown: true

    property real level: -1
    property real labelWidth: 0

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

    function present(): void {
        if (hovered && (title || popoutContent))
            Popouts.show(root, screen, popoutOpts);
    }

    onHoveredChanged: present()
    onPopoutOptsChanged: present()

    readonly property real naturalWidth: row.implicitWidth + Metrics.itemPadding * 2

    implicitWidth: shown ? naturalWidth : 0
    implicitHeight: Metrics.barHeight
    opacity: shown ? 1 : 0
    visible: implicitWidth > 0
    clip: true

    Behavior on implicitWidth {
        Ease {}
    }

    Behavior on opacity {
        NumberAnimation {
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
                Ease {
                    duration: Metrics.shortAnim
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon !== ""
            width: Metrics.iconSize + 4
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
                Ease {
                    duration: Metrics.shortAnim
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
