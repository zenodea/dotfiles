import QtQuick
import qs.services
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

    property bool navigable: true
    readonly property bool focused: Nav.current === root

    implicitHeight: 20

    function activate(): void {
        root.iconClicked();
    }

    function adjust(delta: int): void {
        if (root.adjustable)
            root.moved(Math.max(0, Math.min(1, root.value + delta * 0.05)));
    }

    Component.onCompleted: Nav.register(root)
    Component.onDestruction: Nav.unregister(root)

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -6
        anchors.rightMargin: -6
        anchors.topMargin: -4
        anchors.bottomMargin: -4
        color: "transparent"
        border.width: root.focused ? Metrics.borderWidth : 0
        border.color: Theme.accent
    }

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
