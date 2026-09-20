pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.services
import qs.style

Item {
    id: root

    readonly property real target: 360
    readonly property Notification notif: Notifs.latest
    readonly property bool shown: Notifs.toastShown && !Panels.anyOpen && !!notif
    readonly property alias hitArea: hitArea

    x: 0
    y: Metrics.barHeight
    width: shown ? target : 0
    height: body.implicitHeight + Metrics.popoutPadding * 2

    visible: width > 0
    clip: true

    Behavior on width {
        NumberAnimation {
            duration: Metrics.morphDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: Metrics.emphasized
        }
    }

    Item {
        id: hitArea

        width: root.shown ? root.target : 0
        height: root.height
    }

    Item {
        width: root.target
        height: root.height

        Row {
            id: body

            x: Metrics.popoutPadding
            y: Metrics.popoutPadding
            width: parent.width - Metrics.popoutPadding * 2
            spacing: 10

            Image {
                anchors.verticalCenter: parent.verticalCenter
                visible: source.toString() !== ""
                source: root.notif?.image || (root.notif?.appIcon ? Quickshell.iconPath(root.notif.appIcon, true) : "")
                width: 34
                height: 34
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 68
                sourceSize.height: 68
                asynchronous: true
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - (parent.children[0].visible ? 44 : 0)
                spacing: 2

                Text {
                    width: parent.width
                    text: root.notif?.appName ?? ""
                    visible: text !== ""
                    color: root.notif?.urgency === NotificationUrgency.Critical ? Theme.red : Theme.muted
                    font.family: Theme.fontMono
                    font.pixelSize: 9
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                }

                Text {
                    width: parent.width
                    text: root.notif?.summary ?? ""
                    color: Theme.fgBright
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: root.notif?.body ?? ""
                    color: Theme.fg
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton)
                    root.notif?.dismiss();
                Notifs.hideToast();
            }
        }
    }
}
