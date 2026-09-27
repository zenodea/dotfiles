import QtQuick
import qs.style
import qs.widgets

Rectangle {
    id: root

    required property var item
    required property bool selected
    required property bool hovered

    readonly property var f: item.font ?? ({})
    readonly property bool text: item.kind === "text-font"
    readonly property string requested: (text ? f.family : f.mono) ?? ""
    readonly property bool installed: f.installed ?? false
    readonly property string family: installed ? requested : Theme.fontMono

    function span(c: color, s: string): string {
        return `<font color="${c}">${s}</font>`;
    }

    visible: item.kind !== "blank"
    color: selected ? Theme.alpha(Theme.accent, 0.1) : hovered ? Theme.alpha(Theme.fg, 0.08) : Theme.alpha(Theme.fg, 0.045)

    Behavior on color {
        ColorAnimation {
            duration: Metrics.shortAnim
        }
    }

    Column {
        x: 14
        y: 10
        width: parent.width - 28
        spacing: 6
        opacity: root.installed ? 1 : 0.4

        Text {
            width: parent.width - 24
            text: root.item.label ?? ""
            color: root.selected ? Theme.accent : Theme.fgBright
            font.family: root.family
            font.pixelSize: 16
            elide: Text.ElideRight
            renderType: Text.NativeRendering
        }

        Text {
            width: parent.width
            textFormat: Text.StyledText
            text: root.text ? "The quick brown fox jumps over the lazy dog.<br>Sphinx of black quartz, judge my vow." : [`${root.span(Theme.purple, "const")} ${root.span(Theme.blue, "ok")} = (x) => x != ${root.span(Theme.orange, "0")};`, `0O oO l1I| {}[] -> => ===`].join("<br>")
            color: Theme.fg
            font.family: root.family
            font.pixelSize: 12
            lineHeight: 1.2
            elide: Text.ElideRight
            renderType: Text.NativeRendering
        }
    }

    Label {
        anchors.left: parent.left
        anchors.right: missingTag.visible ? missingTag.left : parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 14
        anchors.bottomMargin: 10
        text: root.requested
        color: Theme.muted
        font.pixelSize: 10
        elide: Text.ElideRight
    }

    Rectangle {
        id: missingTag

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 10
        width: missing.implicitWidth + 12
        height: 18
        color: Theme.alpha(Theme.yellow, 0.15)
        visible: !root.installed

        Label {
            id: missing

            anchors.centerIn: parent
            text: "not installed"
            color: Theme.yellow
            font.pixelSize: 9
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

        Icon {
            anchors.centerIn: parent
            text: "󰄬"
            color: Theme.bg
            font.pixelSize: 13
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
