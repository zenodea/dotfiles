pragma ComponentBehavior: Bound

import QtQuick
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

        ParallelAnimation {
            NumberAnimation {
                target: stack
                property: "opacity"
                to: 0
                duration: Metrics.animDuration
                easing.type: Easing.Bezier
                easing.bezierCurve: Metrics.easeOutQuint
            }

            NumberAnimation {
                target: stack
                property: "scale"
                to: 0.93
                duration: Metrics.animDuration
                easing.type: Easing.Bezier
                easing.bezierCurve: Metrics.easeOutQuint
            }
        }

        ScriptAction {
            script: {
                Notifs.dismissAll();
                stack.opacity = 1;
                stack.scale = 1;
            }
        }
    }

    Label {
        visible: opacity > 0
        opacity: root.recent.length === 0 ? 1 : 0
        text: "Nothing waiting"
        color: Theme.muted

        Behavior on opacity {
            NumberAnimation {
                duration: Metrics.animDuration
            }
        }
    }

    Item {
        width: parent.width
        height: stack.implicitHeight
        visible: height > 0
        clip: true

        Behavior on height {
            Ease {}
        }

        Column {
            id: stack

            width: parent.width
            spacing: 4
            transformOrigin: Item.Top

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
                        duration: Metrics.animDuration
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

                        Label {
                            width: parent.width
                            text: entry.modelData.appName
                            visible: text !== ""
                            color: entry.modelData.urgency === NotificationUrgency.Critical ? Theme.red : Theme.muted
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }

                        Label {
                            width: parent.width
                            text: entry.modelData.summary
                            color: Theme.fgBright
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Label {
                            width: parent.width
                            visible: text !== ""
                            text: entry.modelData.body
                            font.pixelSize: 10
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }

                    Icon {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.top: parent.top
                        anchors.topMargin: 7
                        visible: rowHover.hovered
                        text: "󰅖"
                        color: closeHover.hovered ? Theme.red : Theme.muted
                        font.pixelSize: 12

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
                            if (slideOut.running)
                                return;
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
