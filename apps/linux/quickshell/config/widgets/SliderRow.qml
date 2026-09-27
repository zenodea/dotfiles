import QtQuick
import qs.style

Item {
    id: root

    property string icon: ""
    property color iconColour: Theme.fg
    property string valueText: ""
    property real value: 0
    property color fill: Theme.accent
    property bool adjustable: true

    signal moved(real value)
    signal iconClicked

    implicitHeight: 20

    Icon {
        id: glyph

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon
        color: root.iconColour
        font.pixelSize: 16

        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            onClicked: root.iconClicked()
        }
    }

    Label {
        id: reading

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        width: 34
        text: root.valueText
        color: Theme.muted
        font.pixelSize: 10
    }

    Slider {
        anchors.left: glyph.right
        anchors.right: reading.left
        anchors.leftMargin: 10
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        value: root.value
        fill: root.fill
        enabled: root.adjustable
        onMoved: v => root.moved(v)
    }
}
