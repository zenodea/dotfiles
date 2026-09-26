pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.style
import qs.widgets

Column {
    id: root

    function copy(entry: var): void {
        ClipboardHistory.copy(entry.id);
        Panels.close();
    }

    function forget(entry: var): void {
        ClipboardHistory.forget(entry.id);
    }

    readonly property var shown: {
        const q = search.text.trim().toLowerCase();
        const all = ClipboardHistory.entries;
        if (!q)
            return all;
        return all.filter(e => e.preview.toLowerCase().includes(q));
    }

    spacing: 6

    Component.onCompleted: ClipboardHistory.refresh()

    Text {
        visible: !ClipboardHistory.available
        width: parent.width
        wrapMode: Text.WordWrap
        text: "wl-clipboard is not installed.\n\nsudo pacman -S wl-clipboard"
        color: Theme.muted
        font.family: Theme.fontMono
        font.pixelSize: 11
        renderType: Text.NativeRendering
    }

    Rectangle {
        visible: ClipboardHistory.available
        width: parent.width
        height: 30
        color: Theme.alpha(Theme.fg, 0.06)

        TextInput {
            id: search

            anchors.fill: parent
            anchors.leftMargin: 9
            anchors.rightMargin: 9
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.fgBright
            font.family: Theme.fontMono
            font.pixelSize: 11
            clip: true
            Keys.onEscapePressed: Panels.close()

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: search.text === ""
                text: "Filter clipboard…"
                color: Theme.alpha(Theme.muted, 0.7)
                font: search.font
                renderType: Text.NativeRendering
            }
        }
    }

    Text {
        visible: ClipboardHistory.available && root.shown.length === 0
        text: ClipboardHistory.entries.length === 0 ? "Clipboard history is empty" : "Nothing matches"
        color: Theme.muted
        font.family: Theme.fontMono
        font.pixelSize: 11
        renderType: Text.NativeRendering
    }

    Repeater {
        model: root.shown.slice(0, 50)

        Rectangle {
            id: entry

            required property var modelData

            readonly property bool image: modelData.kind === "image"

            width: root.width
            height: entry.image ? 56 : 42
            color: rowHover.hovered ? Theme.alpha(Theme.accent, 0.12) : Theme.alpha(Theme.fg, 0.04)

            Behavior on color {
                ColorAnimation {
                    duration: Metrics.shortAnim
                }
            }

            Item {
                id: badge

                anchors.left: parent.left
                anchors.leftMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                width: entry.image ? 62 : 16
                height: entry.image ? 40 : 16

                Text {
                    anchors.centerIn: parent
                    visible: !entry.image
                    text: "󰅍"
                    color: rowHover.hovered ? Theme.accent : Theme.muted
                    font.family: Metrics.iconFont
                    font.pixelSize: 13
                    renderType: Text.NativeRendering
                }

                Image {
                    anchors.fill: parent
                    visible: entry.image
                    source: entry.image ? ClipboardHistory.path(entry.modelData.id) : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 124
                    sourceSize.height: 80
                    asynchronous: true
                }
            }

            Text {
                anchors.left: badge.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: entry.image ? `image · ${entry.modelData.preview}` : entry.modelData.preview
                color: Theme.fg
                font.family: Theme.fontMono
                font.pixelSize: 11
                maximumLineCount: 2
                wrapMode: Text.WrapAnywhere
                elide: Text.ElideRight
                renderType: Text.NativeRendering
            }

            HoverHandler {
                id: rowHover
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.copy(entry.modelData)
            }
        }
    }

    Row {
        topPadding: 8
        spacing: 6
        visible: ClipboardHistory.available && ClipboardHistory.entries.length > 0

        PillButton {
            icon: "󰑐"
            label: "Refresh"
            onClicked: ClipboardHistory.refresh()
        }

        PillButton {
            icon: "󰩹"
            label: "Wipe"
            onClicked: ClipboardHistory.wipe()
        }
    }
}
