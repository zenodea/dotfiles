import QtQuick
import Quickshell
import qs.services
import qs.style
import qs.widgets

Rectangle {
    id: root

    width: 300
    height: 46
    color: Theme.alpha(Theme.surface, 0.6)
    radius: Metrics.frameRadius
    border.width: Metrics.borderWidth
    border.color: Lock.checking ? Theme.yellow : Lock.buffer !== "" ? Theme.accent : Theme.alpha(Theme.fg, 0.15)
    focus: true

    Behavior on border.color {
        ColorAnimation {
            duration: Metrics.shortAnim
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            Lock.submit();
        else if (event.key === Qt.Key_Backspace)
            Lock.erase(event.modifiers & Qt.ControlModifier);
        else if (event.key === Qt.Key_Escape)
            Lock.erase(true);
        else if (event.text.length > 0 && event.text.charCodeAt(0) >= 32)
            Lock.type(event.text);
        event.accepted = true;
    }

    Connections {
        function onFailed(): void {
            shake.restart();
        }

        target: Lock
    }

    SequentialAnimation {
        id: shake

        loops: 2

        NumberAnimation {
            target: nudge
            property: "x"
            to: 8
            duration: 40
        }

        NumberAnimation {
            target: nudge
            property: "x"
            to: -8
            duration: 80
        }

        NumberAnimation {
            target: nudge
            property: "x"
            to: 0
            duration: 40
        }
    }

    transform: Translate {
        id: nudge
    }

    Icon {
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: "󰌾"
        color: Lock.fails > 0 && Lock.buffer === "" ? Theme.red : Theme.muted
        font.pixelSize: Metrics.iconSize
    }

    Label {
        anchors.centerIn: parent
        visible: Lock.buffer === ""
        text: Quickshell.env("USER") ?? "password"
        color: Theme.muted
        font.pixelSize: Metrics.fontSize
    }

    Row {
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width - 80)
        spacing: 6
        clip: true
        layoutDirection: Qt.RightToLeft

        Repeater {
            model: Lock.buffer.length

            Rectangle {
                width: 8
                height: 8
                radius: 4
                color: Lock.checking ? Theme.muted : Theme.fgBright
            }
        }
    }
}
