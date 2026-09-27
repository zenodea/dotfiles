import QtQuick
import qs.style

Rectangle {
    id: root

    property string icon: ""
    property bool enabled: true
    property int size: Metrics.iconSize

    signal clicked

    implicitWidth: size + 10
    implicitHeight: size + 6
    radius: Metrics.radius
    color: area.containsMouse && enabled ? Theme.alpha(Theme.fg, 0.1) : "transparent"

    Behavior on color {
        ColorAnimation {
            duration: Metrics.shortAnim
        }
    }

    Icon {
        anchors.centerIn: parent
        text: root.icon
        color: !root.enabled ? Theme.alpha(Theme.muted, 0.4) : area.containsMouse ? Theme.accent : Theme.fg
        font.pixelSize: root.size

        Behavior on color {
            ColorAnimation {
                duration: Metrics.shortAnim
            }
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        onClicked: root.clicked()
    }
}
