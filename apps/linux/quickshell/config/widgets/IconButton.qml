import QtQuick
import qs.services
import qs.style

Rectangle {
    id: root

    property string icon: ""
    property bool enabled: true
    property int size: Metrics.iconSize

    signal clicked

    property bool navigable: true
    readonly property bool focused: Nav.current === root

    implicitWidth: size + 10
    implicitHeight: size + 6
    radius: Metrics.radius
    border.width: focused ? Metrics.borderWidth : 0
    border.color: Theme.accent

    function activate(): void {
        if (root.enabled)
            root.clicked();
    }

    Component.onCompleted: Nav.register(root)
    Component.onDestruction: Nav.unregister(root)
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
