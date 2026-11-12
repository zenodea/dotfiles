import QtQuick
import qs.style
import qs.widgets

Row {
    property alias icon: glyph.text
    property alias iconColor: glyph.color
    property alias text: label.text

    spacing: Metrics.gap

    Icon {
        id: glyph

        anchors.verticalCenter: parent.verticalCenter
        color: Theme.accent
        font.pixelSize: Metrics.iconSize
    }

    Label {
        id: label

        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, 260)
        elide: Text.ElideRight
        font.pixelSize: Metrics.fontSize
    }
}
