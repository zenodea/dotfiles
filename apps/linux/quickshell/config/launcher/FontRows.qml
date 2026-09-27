import QtQuick
import qs.style
import qs.widgets

// MONO / TEXT row labels and dividers drawn over the font grid
Item {
    id: root

    readonly property int gutter: 34

    Repeater {
        model: ["MONO", "TEXT"]

        Label {
            required property int index
            required property string modelData

            x: (root.gutter - height) / 2
            y: index * root.height / 2 + root.height / 4 + width / 2
            transformOrigin: Item.TopLeft
            rotation: -90
            text: modelData
            color: Theme.accent
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 3
        }
    }

    Rectangle {
        x: root.gutter - 1
        width: Metrics.borderWidth
        height: parent.height
        color: Theme.alpha(Theme.fg, 0.15)
    }

    Rectangle {
        y: Math.round(parent.height / 2)
        width: parent.width
        height: Metrics.borderWidth
        color: Theme.alpha(Theme.fg, 0.15)
    }
}
