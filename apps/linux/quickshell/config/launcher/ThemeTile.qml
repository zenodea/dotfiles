import QtQuick
import qs.style
import qs.widgets

Item {
    id: root

    required property var item
    required property bool selected
    required property bool hovered

    readonly property var t: item.theme ?? ({})

    function span(c: string, s: string): string {
        return `<font color="${c}">${s}</font>`;
    }

    opacity: selected ? 1 : hovered ? 0.95 : 0.75

    Behavior on opacity {
        NumberAnimation {
            duration: Metrics.shortAnim
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.t.bg ?? "transparent"
    }

    Image {
        id: wall

        anchors.right: parent.right
        width: Math.round(parent.width * 0.34)
        height: parent.height
        source: root.t.thumb ?? ""
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 480
        asynchronous: true
        visible: status === Image.Ready
    }

    Column {
        x: 10
        y: 9
        width: parent.width - (wall.visible ? wall.width : 0) - 20
        spacing: 6

        Row {
            width: parent.width
            spacing: 6

            Icon {
                text: root.item.light ? "󰖨" : "󰖔"
                color: root.t.accent ?? Theme.accent
                font.pixelSize: 12
            }

            Label {
                width: parent.width - 18
                text: root.item.label ?? ""
                color: root.t.fg ?? Theme.fg
                font.bold: true
                elide: Text.ElideRight
            }
        }

        Rectangle {
            width: 28
            height: 2
            color: root.t.accent ?? Theme.accent
        }

        Label {
            width: parent.width
            textFormat: Text.StyledText
            text: {
                const t = root.t;
                if (!t.bg)
                    return "";
                return [`${root.span(t.purple, "fn")} ${root.span(t.blue, "greet")}${root.span(t.fg, "(n) {")}`, `  ${root.span(t.purple, "if")} ${root.span(t.fg, "n >")} ${root.span(t.orange, "0")} ${root.span(t.fg, "{")}`, `    ${root.span(t.yellow, "say")}${root.span(t.fg, "(")}${root.span(t.green, "\"hi\"")}${root.span(t.fg, ")")}`, `  ${root.span(t.fg, "}")} ${root.span(t.red, "// todo")}`, root.span(t.fg, "}")].join("<br>");
            }
            font.pixelSize: 9
            lineHeight: 1.1
            clip: true
        }
    }

    Row {
        x: 10
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 9
        spacing: 3

        Repeater {
            model: ["red", "orange", "yellow", "green", "blue", "purple"]

            Rectangle {
                required property string modelData

                width: 9
                height: 9
                color: root.t[modelData] ?? "transparent"
            }
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
