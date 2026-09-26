import QtQuick
import qs.style

Item {
    id: root

    required property var item
    required property bool selected
    required property bool hovered

    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(Theme.fg, 0.045)
    }

    Image {
        id: thumb

        anchors.fill: parent
        source: root.item.thumb ?? ""
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 480
        asynchronous: true
        opacity: status !== Image.Ready ? 0 : root.selected ? 1 : root.hovered ? 0.85 : 0.55

        Behavior on opacity {
            NumberAnimation {
                duration: Metrics.shortAnim
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 24
        color: Theme.alpha(Theme.bg, 0.8)
        visible: root.selected || root.hovered

        Text {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: Text.AlignVCenter
            text: root.item.label ?? ""
            color: root.selected ? Theme.accent : Theme.fg
            font.family: Theme.fontMono
            font.pixelSize: 11
            elide: Text.ElideRight
            renderType: Text.NativeRendering
        }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 6
        width: 20
        height: 20
        color: Theme.accent
        visible: root.item.current ?? false

        Text {
            anchors.centerIn: parent
            text: "󰄬"
            color: Theme.bg
            font.family: Metrics.iconFont
            font.pixelSize: 13
            renderType: Text.NativeRendering
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 2
        border.color: Theme.accent
        visible: root.selected
    }
}
