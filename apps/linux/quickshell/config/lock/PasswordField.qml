import QtQuick
import qs.services
import qs.style
import qs.widgets

Rectangle {
    id: root

    property QtObject auth: Lock

    width: 300
    height: 46
    color: Theme.alpha(Theme.surface, 0.6)
    radius: Metrics.frameRadius
    border.width: Metrics.borderWidth
    border.color: root.auth.checking ? Theme.yellow : root.auth.buffer !== "" ? Theme.accent : Theme.alpha(Theme.fg, 0.15)
    focus: true

    Behavior on border.color {
        ColorAnimation {
            duration: Metrics.shortAnim
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            root.auth.submit();
        else if (event.key === Qt.Key_Backspace)
            root.auth.erase(event.modifiers & Qt.ControlModifier);
        else if (event.key === Qt.Key_Escape)
            root.auth.erase(true);
        else if (event.text.length > 0 && event.text.charCodeAt(0) >= 32)
            root.auth.type(event.text);
        else
            return;
        event.accepted = true;
    }

    Connections {
        function onFailed(): void {
            shake.restart();
        }

        target: root.auth
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
        color: root.auth.fails > 0 && root.auth.buffer === "" ? Theme.red : Theme.muted
        font.pixelSize: Metrics.iconSize
    }

    Icon {
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        visible: root.auth.fingerprint
        text: "󰈷"
        color: Theme.muted
        font.pixelSize: Metrics.iconSize
    }

    Label {
        anchors.centerIn: parent
        visible: root.auth.buffer === ""
        text: root.auth.user || "password"
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
            model: root.auth.buffer.length

            Rectangle {
                width: 8
                height: 8
                radius: 4
                color: root.auth.checking ? Theme.muted : Theme.fgBright
            }
        }
    }
}
