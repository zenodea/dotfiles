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

    readonly property MprisPlayer player: Media.player

    readonly property bool hasPlayer: !!player
    readonly property bool playing: player?.isPlaying ?? false
    readonly property string art: player?.trackArtUrl ?? ""

    function truncate(s: string, n: int): string {
        if (!s)
            return "";
        return s.length > n ? `${s.slice(0, n - 1)}…` : s;
    }

    implicitWidth: row.implicitWidth + Metrics.itemPadding * 2
    implicitHeight: Metrics.barHeight
    color: "transparent"

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: Metrics.sectionSpacing

        transform: Translate {
            y: area.containsMouse ? -1 : 0

            Behavior on y {
                Morph {
                    duration: Metrics.shortAnim
                }
            }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(root.now, "HH:mm")
                color: area.containsMouse ? Theme.accent : Theme.fgBright
                font.pixelSize: 15
                font.bold: true

                Behavior on color {
                    ColorAnimation {
                        duration: Metrics.shortAnim
                    }
                }
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Metrics.borderWidth
            height: root.hasPlayer ? 14 : 0
            color: Theme.alpha(Theme.fg, 0.25)

            Behavior on height {
                Ease {}
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
                Ease {}
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
                        asynchronous: true
                    }

                    Icon {
                        anchors.centerIn: parent
                        visible: root.art === ""
                        text: root.playing ? "󰏤" : "󰐊"
                        color: Theme.muted
                        font.pixelSize: Metrics.iconSize
                    }
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.truncate(root.player?.trackTitle ?? "", 28)
                    color: area.containsMouse ? Theme.accent : root.playing ? Theme.fg : Theme.muted
                    font.pixelSize: Metrics.fontSize

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
            spacing: 12

            Column {
                spacing: 2

                PopoutTitle {
                    font.pixelSize: 16
                    text: Qt.formatDateTime(root.now, "dddd, d MMMM")
                }

                PopoutLabel {
                    font.pixelSize: 13
                    text: Qt.formatDateTime(root.now, "yyyy-MM-dd · HH:mm")
                }
            }

            Rectangle {
                visible: root.hasPlayer
                width: parent.width
                height: Metrics.borderWidth
                color: Theme.alpha(Theme.fg, 0.15)
            }

            MediaCard {
                textWidth: 340
            }

            Rectangle {
                visible: Media.many
                width: parent.width
                height: Metrics.borderWidth
                color: Theme.alpha(Theme.fg, 0.15)
            }

            Row {
                id: sources

                visible: Media.many
                width: parent.width
                spacing: 1

                readonly property real cell: Media.players.length > 0 ? (width - (Media.players.length - 1)) / Media.players.length : width

                Repeater {
                    model: Media.players

                    Rectangle {
                        id: source

                        required property var modelData

                        readonly property bool current: Media.key(modelData) === Media.key(Media.player)

                        width: sources.cell
                        height: 34
                        color: current ? Theme.alpha(Theme.accent, 0.18) : sourceHover.hovered ? Theme.alpha(Theme.fg, 0.08) : Theme.alpha(Theme.fg, 0.04)

                        Behavior on color {
                            ColorAnimation {
                                duration: Metrics.shortAnim
                            }
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 8

                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: source.toString() !== ""
                                source: Media.icon(source.modelData)
                                width: 18
                                height: 18
                                sourceSize.width: 36
                                sourceSize.height: 36
                                asynchronous: true
                            }

                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Media.label(source.modelData)
                                color: source.current ? Theme.accent : Theme.fg
                                font.pixelSize: 12
                            }
                        }

                        HoverHandler {
                            id: sourceHover
                        }

                        TapHandler {
                            onTapped: Media.select(source.modelData)
                        }
                    }
                }
            }
        }
    }
}
