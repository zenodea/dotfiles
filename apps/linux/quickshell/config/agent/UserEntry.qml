import QtQuick
import qs.style
import qs.widgets

Row {
    id: root

    required property string text

    width: ListView.view.width
    spacing: Metrics.gap

    Label {
        text: "›"
        color: Theme.accent
        font.pixelSize: 14
    }

    Label {
        width: root.width - 14
        wrapMode: Text.Wrap
        text: root.text
        color: Theme.fgBright
        font.pixelSize: 14
    }
}
