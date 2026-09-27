import QtQuick
import qs.style

Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property string detail: ""
    property bool active: false

    signal clicked

    implicitHeight: 30
    color: active ? Theme.alpha(Theme.accent, 0.15) : area.containsMouse ? Theme.alpha(Theme.fg, 0.07) : "transparent"

    Behavior on color {
        ColorAnimation {
            duration: Metrics.shortAnim
        }
    }

    Icon {
        id: glyph

        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        text: root.icon
        color: root.active ? Theme.accent : Theme.muted
    }

    Label {
        id: note

        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.detail
        color: Theme.muted
        font.pixelSize: 10
    }

    Label {
        anchors.left: glyph.right
        anchors.leftMargin: 6
        anchors.right: note.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: root.active ? Theme.accent : Theme.fg
        elide: Text.ElideRight
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
