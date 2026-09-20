import QtQuick
import qs.style

Column {
    id: root

    property string title: ""
    default property alias content: holder.data

    spacing: 6

    Text {
        text: root.title.toUpperCase()
        visible: root.title !== ""
        color: Theme.muted
        font.family: Theme.fontMono
        font.pixelSize: 10
        font.letterSpacing: 1
        renderType: Text.NativeRendering
    }

    Column {
        id: holder

        width: root.width
        spacing: 4
    }
}
