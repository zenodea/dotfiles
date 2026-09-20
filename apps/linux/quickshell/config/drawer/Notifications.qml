pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.services
import qs.style
import qs.widgets

Column {
    id: root

    readonly property var recent: Notifs.all.slice().reverse()

    spacing: 6

    SequentialAnimation {
        id: clearAll

        NumberAnimation {
            target: stack
            property: "x"
            to: root.width + 60
            duration: Metrics.morphDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: Metrics.emphasized
        }

        ScriptAction {
            script: {
                Notifs.dismissAll();
                stack.x = 0;
            }
        }
    }

    Text {
        visible: root.recent.length === 0
        text: "Nothing waiting"
        color: Theme.muted
        font.family: Theme.fontMono
        font.pixelSize: 11
        renderType: Text.NativeRendering
    }

    Column {
        id: stack

        width: parent.width
        spacing: 4

        Repeater {
            model: root.recent.slice(0, 8)

            Rectangle {
                id: entry

                required property Notification modelData

                width: stack.width
                height: layout.implicitHeight + 14
                color: rowHover.hovered ? Theme.alpha(Theme.fg, 0.07) : "transparent"

                Behavior on color {
                    ColorAnimation {
                        duration: Metrics.shortAnim
                    }
                }

                NumberAnimation {
                    id: slideOut

                    target: entry
                    property: "x"
                    to: entry.width + 60
                    duration: Metrics.morphDuration
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Metrics.emphasized
                    onFinished: entry.modelData.dismiss()
                }

                HoverHandler {
                    id: rowHover
                }

                Column {
                    id: layout

                    x: 2
                    y: 7
                    width: parent.width - 34
                    spacing: 1

                    Text {
                        width: parent.width
                        text: entry.modelData.appName
                        visible: text !== ""
                        color: entry.modelData.urgency === NotificationUrgency.Critical ? Theme.red : Theme.muted
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                    }

                    Text {
                        width: parent.width
                        text: entry.modelData.summary
                        color: Theme.fgBright
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        font.bold: true
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: entry.modelData.body
                        color: Theme.fg
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.top: parent.top
                    anchors.topMargin: 7
                    visible: rowHover.hovered
                    text: "󰅖"
                    color: closeHover.hovered ? Theme.red : Theme.muted
                    font.family: Metrics.iconFont
                    font.pixelSize: 12
                    renderType: Text.NativeRendering

                    HoverHandler {
                        id: closeHover
                    }

                    TapHandler {
                        margin: 6
                        onTapped: slideOut.start()
                    }
                }

                TapHandler {
                    onTapped: {
                        const actions = entry.modelData.actions;
                        if (actions.length > 0) {
                            actions[0].invoke();
                            Panels.close();
                        }
                    }
                }
            }
        }
    }

    Item {
        width: 1
        height: 2
        visible: root.recent.length > 0
    }

    PillButton {
        visible: root.recent.length > 0
        icon: "󰎟"
        label: root.recent.length > 8 ? `Clear all (${root.recent.length})` : "Clear all"
        onClicked: clearAll.restart()
    }
}
