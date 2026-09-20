import QtQuick
import qs.style

Rectangle {
    id: root

    property bool selected: false
    property bool current: false
    default property alias content: holder.data

    signal activated

    implicitHeight: 34
    color: selected ? Theme.alpha(Theme.accent, 0.15) : area.containsMouse ? Theme.alpha(Theme.fg, 0.07) : "transparent"

    Behavior on color {
        ColorAnimation {
            duration: Metrics.shortAnim
        }
    }

    Rectangle {
        width: 2
        height: parent.height
        color: Theme.accent
        visible: root.current
    }

    Item {
        id: holder

        anchors.fill: parent
        anchors.leftMargin: Metrics.popoutPadding
        anchors.rightMargin: Metrics.popoutPadding
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.activated()
    }
}
