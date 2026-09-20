pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.style
import qs.services
import qs.widgets

Rectangle {
    id: root

    property ShellScreen screen: null

    readonly property date now: clock.date

    readonly property MprisPlayer player: {
        const players = Mpris.players.values;
        return players.find(p => p.isPlaying) ?? players[0] ?? null;
    }

    readonly property bool hasPlayer: !!player
    readonly property bool playing: player?.isPlaying ?? false
    readonly property string art: player?.trackArtUrl ?? ""

    property real position: 0

    function truncate(s: string, n: int): string {
        if (!s)
            return "";
        return s.length > n ? `${s.slice(0, n - 1)}…` : s;
    }

    function clockText(seconds: real): string {
        if (!seconds || seconds < 0)
            return "0:00";
        const total = Math.floor(seconds);
        const m = Math.floor(total / 60);
        const s = total % 60;
        return `${m}:${s < 10 ? "0" : ""}${s}`;
    }

    implicitWidth: row.implicitWidth + Metrics.itemPadding * 2
    implicitHeight: Metrics.barHeight
    color: "transparent"

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    Timer {
        running: root.playing
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.position = root.player?.position ?? 0
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: Metrics.sectionSpacing

        transform: Translate {
            y: area.containsMouse ? -1 : 0

            Behavior on y {
                NumberAnimation {
                    duration: Metrics.shortAnim
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Metrics.emphasized
                }
            }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(root.now, "hh:mm")
                color: area.containsMouse ? Theme.accent : Theme.fgBright
                font.family: Theme.fontMono
                font.pixelSize: 15
                font.bold: true
                renderType: Text.NativeRendering

                Behavior on color {
                    ColorAnimation {
                        duration: Metrics.shortAnim
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(root.now, "AP")
                color: Theme.muted
                font.family: Theme.fontMono
                font.pixelSize: 9
                renderType: Text.NativeRendering
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Metrics.borderWidth
            height: root.hasPlayer ? 14 : 0
            color: Theme.alpha(Theme.fg, 0.25)

            Behavior on height {
                NumberAnimation {
                    duration: Metrics.animDuration
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Metrics.easeOutQuint
                }
            }
        }

        Item {
            id: track

            anchors.verticalCenter: parent.verticalCenter

            readonly property real naturalWidth: trackRow.implicitWidth

            width: root.hasPlayer ? naturalWidth : 0
            height: Metrics.barHeight
            opacity: root.hasPlayer ? 1 : 0
            clip: true

            Behavior on width {
                NumberAnimation {
                    duration: Metrics.animDuration
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Metrics.easeOutQuint
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: Metrics.shortAnim
                }
            }

            Row {
                id: trackRow

                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.gap

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Metrics.iconSize
                    height: Metrics.iconSize

                    Image {
                        anchors.fill: parent
                        visible: root.art !== ""
                        source: root.art
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 32
                        sourceSize.height: 32
                        smooth: true
                        asynchronous: true
                        cache: true
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: root.art === ""
                        text: root.playing ? "󰏤" : "󰐊"
                        color: Theme.muted
                        font.family: Metrics.iconFont
                        font.pixelSize: Metrics.iconSize
                        renderType: Text.NativeRendering
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.truncate(root.player?.trackTitle ?? "", 28)
                    color: area.containsMouse ? Theme.accent : root.playing ? Theme.fg : Theme.muted
                    font.family: Theme.fontMono
                    font.pixelSize: Metrics.fontSize
                    renderType: Text.NativeRendering

                    Behavior on color {
                        ColorAnimation {
                            duration: Metrics.shortAnim
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        onEntered: Popouts.show(root, root.screen, {
                content: panel
            })
        onClicked: root.player?.togglePlaying()
        onWheel: wheel => {
            if (!root.hasPlayer)
                return;
            if (wheel.angleDelta.y > 0)
                root.player?.next();
            else
                root.player?.previous();
        }
    }

    Component {
        id: panel

        Column {
            spacing: 8

            Column {
                spacing: 1

                PopoutTitle {
                    text: Qt.formatDateTime(root.now, "dddd, d MMMM")
                }

                PopoutLabel {
                    text: Qt.formatDateTime(root.now, "yyyy-MM-dd · hh:mm AP")
                }
            }

            Rectangle {
                visible: root.hasPlayer
                width: parent.width
                height: Metrics.borderWidth
                color: Theme.alpha(Theme.fg, 0.15)
            }

            Row {
                visible: root.hasPlayer
                spacing: Metrics.popoutPadding

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.art !== ""
                    source: root.art
                    width: 64
                    height: 64
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 128
                    sourceSize.height: 128
                    smooth: true
                    asynchronous: true
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    PopoutTitle {
                        text: root.player?.trackTitle ?? ""
                        width: Math.min(implicitWidth, 240)
                        elide: Text.ElideRight
                    }

                    PopoutLabel {
                        text: root.player?.trackArtist ?? ""
                        width: Math.min(implicitWidth, 240)
                        elide: Text.ElideRight
                    }

                    PopoutLabel {
                        text: root.player?.trackAlbum ?? ""
                        width: Math.min(implicitWidth, 240)
                        elide: Text.ElideRight
                    }

                    Item {
                        width: 1
                        height: 4
                    }

                    Rectangle {
                        visible: (root.player?.lengthSupported ?? false) && (root.player?.length ?? 0) > 0
                        width: 200
                        height: 3
                        color: Theme.alpha(Theme.fg, 0.15)

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, root.position / Math.max(1, root.player?.length ?? 1)))
                            height: parent.height
                            color: Theme.accent

                            Behavior on width {
                                NumberAnimation {
                                    duration: Metrics.shortAnim
                                }
                            }
                        }
                    }

                    Row {
                        spacing: Metrics.gap

                        PopoutLabel {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: (root.player?.lengthSupported ?? false) && (root.player?.length ?? 0) > 0
                            text: `${root.clockText(root.position)} / ${root.clockText(root.player?.length ?? 0)}`
                        }

                        Item {
                            width: Metrics.gap
                            height: 1
                        }

                        IconButton {
                            icon: "󰒮"
                            enabled: root.player?.canGoPrevious ?? false
                            onClicked: root.player?.previous()
                        }

                        IconButton {
                            icon: root.playing ? "󰏤" : "󰐊"
                            enabled: root.player?.canTogglePlaying ?? false
                            onClicked: root.player?.togglePlaying()
                        }

                        IconButton {
                            icon: "󰒭"
                            enabled: root.player?.canGoNext ?? false
                            onClicked: root.player?.next()
                        }
                    }
                }
            }
        }
    }
}
