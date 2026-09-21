import QtQuick
import Quickshell
import qs.style

Row {
    id: root

    required property var item

    spacing: Metrics.gap + 2

    Image {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.item.kind === "app"
        source: root.item.kind === "app" ? Quickshell.iconPath(root.item.entry.icon, true) : ""
        width: 22
        height: 22
        sourceSize.width: 44
        sourceSize.height: 44
        asynchronous: true
    }

    Image {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.item.kind === "wallpaper"
        source: root.item.kind === "wallpaper" ? root.item.thumb : ""
        width: 56
        height: 32
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 112
        sourceSize.height: 64
        asynchronous: true
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.item.kind === "theme"
        spacing: 2

        Rectangle {
            width: 10
            height: 22
            color: root.item.theme?.bg ?? "transparent"
        }

        Rectangle {
            width: 10
            height: 22
            color: root.item.theme?.fg ?? "transparent"
        }

        Rectangle {
            width: 10
            height: 22
            color: root.item.theme?.accent ?? "transparent"
        }
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.item.kind === "font"
        width: 34
        height: 30
        color: Theme.alpha(Theme.fg, 0.07)

        Text {
            anchors.centerIn: parent
            text: "Aa"
            color: root.item.font?.installed ? Theme.fgBright : Theme.alpha(Theme.muted, 0.7)
            font.family: root.item.font?.installed ? root.item.font.mono : Theme.fontMono
            font.pixelSize: 15
            renderType: Text.NativeRendering
        }
    }

    Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 80

        Text {
            width: parent.width
            text: root.item.name
            color: Theme.fg
            font.family: Theme.fontMono
            font.pixelSize: 12
            elide: Text.ElideRight
            renderType: Text.NativeRendering
        }

        Text {
            width: parent.width
            visible: (root.item.sub ?? "") !== ""
            text: root.item.sub ?? ""
            color: Theme.muted
            font.family: Theme.fontMono
            font.pixelSize: 9
            elide: Text.ElideRight
            renderType: Text.NativeRendering
        }
    }
}
