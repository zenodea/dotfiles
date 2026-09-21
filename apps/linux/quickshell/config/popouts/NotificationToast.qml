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
    readonly property bool notice: Notices.active
    property bool showingNotice: false

    onNoticeChanged: {
        if (notice)
            showingNotice = true;
    }

    onShownChanged: {
        if (shown)
            showingNotice = notice;
    }

    readonly property string appName: showingNotice ? "" : notif?.appName ?? ""
    readonly property string summary: showingNotice ? Notices.summary : notif?.summary ?? ""
    readonly property string body: showingNotice ? Notices.body : notif?.body ?? ""
    readonly property string glyph: showingNotice ? Notices.icon : ""
    readonly property string image: showingNotice ? "" : root.notif?.image || (root.notif?.appIcon ? Quickshell.iconPath(root.notif.appIcon, true) : "")

    readonly property bool shown: !Panels.anyOpen && (notice || (Notifs.toastShown && !!notif))
    readonly property alias hitArea: hitArea

    y: Metrics.barHeight
    width: shown ? target : 0
    height: content.implicitHeight + Metrics.popoutPadding * 2

    visible: width > 0
    clip: true

    Behavior on width {
        Morph {}
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
            id: content

            x: Metrics.popoutPadding
            y: Metrics.popoutPadding
            width: parent.width - Metrics.popoutPadding * 2
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.glyph !== ""
                text: root.glyph
                color: Theme.accent
                font.family: Metrics.iconFont
                font.pixelSize: 24
                renderType: Text.NativeRendering
            }

            Image {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.image !== ""
                source: root.image
                width: 34
                height: 34
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 68
                sourceSize.height: 68
                asynchronous: true
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - (root.glyph !== "" ? 34 : 0) - (root.image !== "" ? 44 : 0)
                spacing: 2

                Text {
                    width: parent.width
                    text: root.appName
                    visible: text !== ""
                    color: root.notif?.urgency === NotificationUrgency.Critical ? Theme.red : Theme.muted
                    font.family: Theme.fontMono
                    font.pixelSize: 9
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                }

                Text {
                    width: parent.width
                    text: root.summary
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
                    text: root.body
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
                if (root.showingNotice) {
                    Notices.active = false;
                    return;
                }
                if (mouse.button === Qt.RightButton)
                    root.notif?.dismiss();
                Notifs.hideToast();
            }
        }
    }
}
