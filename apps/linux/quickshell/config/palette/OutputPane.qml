import QtQuick
import qs.style
import qs.widgets

Flickable {
    id: root

    property var runner: null

    readonly property bool pinned: contentY >= contentHeight - height - 2

    function scroll(by: real): void {
        contentY = Math.max(0, Math.min(contentY + by, Math.max(0, contentHeight - height)));
    }

    contentWidth: width
    contentHeight: output.implicitHeight + 20
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    onContentHeightChanged: {
        if (runner?.running)
            contentY = Math.max(0, contentHeight - height);
    }

    Momentum {}

    Label {
        id: output

        x: 14
        y: 10
        width: root.width - 28
        text: root.runner?.text || (root.runner?.running ? "" : "(no output)")
        color: root.runner?.text ? Theme.fg : Theme.muted
        font.pixelSize: 12
        lineHeight: 1.25
        wrapMode: Text.WrapAnywhere
        textFormat: Text.PlainText
    }
}
