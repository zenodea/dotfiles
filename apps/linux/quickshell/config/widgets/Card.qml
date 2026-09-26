import QtQuick
import qs.style

Rectangle {
    id: root

    property string title: ""
    property int padding: 12
    default property alias content: holder.data

    implicitHeight: holder.implicitHeight + padding * 2 + (title ? heading.implicitHeight + 8 : 0)
    color: Theme.surface

    Text {
        id: heading

        x: root.padding
        y: root.padding
        visible: root.title !== ""
        text: root.title.toUpperCase()
        color: Theme.muted
        font.family: Theme.fontMono
        font.pixelSize: 9
        font.letterSpacing: 1.2
        renderType: Text.NativeRendering
    }

    Column {
        id: holder

        x: root.padding
        y: root.padding + (root.title ? heading.implicitHeight + 8 : 0)
        width: root.width - root.padding * 2
        spacing: 6
    }
}
