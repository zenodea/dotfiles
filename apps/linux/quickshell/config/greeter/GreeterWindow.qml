import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.style
import qs.widgets

PanelWindow {
    id: root

    property bool shown: false
    readonly property real visibility: shown && !Greeter.done ? 1 : 0

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: Theme.bg
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "greeter"

    Component.onCompleted: shown = true

    GreeterContent {
        anchors.centerIn: parent
        opacity: root.visibility
        scale: 0.96 + 0.04 * opacity

        Behavior on opacity {
            NumberAnimation {
                duration: Metrics.lockDuration
                easing.type: Easing.InOutCubic
            }
        }
    }

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        spacing: 4
        opacity: root.visibility

        Behavior on opacity {
            NumberAnimation {
                duration: Metrics.lockDuration
                easing.type: Easing.InOutCubic
            }
        }

        PowerButton {
            icon: "󰤄"
            action: "suspend"
        }

        PowerButton {
            icon: "󰑓"
            action: "reboot"
        }

        PowerButton {
            icon: "󰐥"
            action: "poweroff"
        }
    }

    component PowerButton: Rectangle {
        id: button

        property alias icon: glyph.text
        property string action: ""

        width: 40
        height: 40
        radius: Metrics.frameRadius
        color: area.containsMouse ? Theme.alpha(Theme.fg, 0.1) : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Metrics.shortAnim
            }
        }

        Icon {
            id: glyph

            anchors.centerIn: parent
            color: area.containsMouse ? Theme.accent : Theme.muted
            font.pixelSize: Metrics.iconSize + 2
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Greeter.power(button.action)
        }
    }
}
