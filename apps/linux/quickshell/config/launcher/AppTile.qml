import QtQuick
import Quickshell
import qs.style
import qs.widgets

Rectangle {
    id: root

    required property var item
    required property bool selected
    required property bool hovered
    required property string query

    function htmlSafe(s: string): string {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function marked(name: string): string {
        const q = query.trim();
        const at = q ? name.toLowerCase().indexOf(q.toLowerCase()) : -1;
        if (at < 0)
            return htmlSafe(name);
        return `${htmlSafe(name.slice(0, at))}<font color="${Theme.accent}"><b>${htmlSafe(name.slice(at, at + q.length))}</b></font>${htmlSafe(name.slice(at + q.length))}`;
    }

    color: selected ? Theme.alpha(Theme.accent, 0.15) : hovered ? Theme.alpha(Theme.fg, 0.08) : "transparent"

    Behavior on color {
        ColorAnimation {
            duration: Metrics.shortAnim
        }
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - 16
        spacing: 8

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: root.item.icon ?? ""
            width: 44
            height: 44
            sourceSize.width: 88
            sourceSize.height: 88
            asynchronous: true
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.StyledText
            text: root.marked(root.item.name ?? "")
            color: root.selected ? Theme.fgBright : Theme.fg
            elide: Text.ElideRight
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: root.selected && text !== ""
            text: root.item.sub ?? ""
            color: Theme.muted
            font.pixelSize: 9
            elide: Text.ElideRight
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
