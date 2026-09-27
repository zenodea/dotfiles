pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Mpris
import qs.services
import qs.style

Item {
    id: root

    property int artSize: 96
    property int textWidth: 340

    readonly property MprisPlayer player: Media.player

    readonly property bool playing: player?.isPlaying ?? false
    readonly property string art: player?.trackArtUrl ?? ""
    readonly property bool hasLength: (player?.lengthSupported ?? false) && (player?.length ?? 0) > 0

    property real position: 0

    function clockText(seconds: real): string {
        if (!seconds || seconds < 0)
            return "0:00";
        const total = Math.floor(seconds);
        const m = Math.floor(total / 60);
        const s = total % 60;
        return `${m}:${s < 10 ? "0" : ""}${s}`;
    }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    visible: !!player

    function sync(): void {
        root.position = root.player?.position ?? 0;
    }

    onVisibleChanged: sync()
    onPlayerChanged: sync()
    onPlayingChanged: sync()

    Connections {
        function onPostTrackChanged(): void {
            root.sync();
        }

        target: root.player
    }

    Timer {
        running: root.visible && !!root.player
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sync()
    }

    Row {
        id: row

        spacing: Metrics.popoutPadding

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: root.artSize
            height: root.artSize
            color: Theme.alpha(Theme.fg, 0.07)

            Icon {
                anchors.centerIn: parent
                visible: cover.status !== Image.Ready
                text: "󰝚"
                color: Theme.alpha(Theme.muted, 0.8)
                font.pixelSize: root.artSize / 2.4
            }

            Image {
                id: cover

                anchors.fill: parent
                source: root.art
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: root.artSize * 2
                sourceSize.height: root.artSize * 2
                asynchronous: true
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Label {
                text: root.player?.trackTitle ?? ""
                color: Theme.fgBright
                font.pixelSize: 15
                font.bold: true
                width: root.textWidth
                elide: Text.ElideRight
            }

            Label {
                text: root.player?.trackArtist ?? ""
                color: Theme.muted
                font.pixelSize: 12
                width: root.textWidth
                elide: Text.ElideRight
            }

            Label {
                text: root.player?.trackAlbum ?? ""
                color: Theme.muted
                font.pixelSize: 12
                width: root.textWidth
                elide: Text.ElideRight
            }

            Item {
                width: 1
                height: 4
            }

            Rectangle {
                width: root.textWidth - 20
                height: 5
                opacity: root.hasLength ? 1 : 0.35
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

            Item {
                width: 1
                height: 2
            }

            Row {
                spacing: Metrics.gap

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 10
                    spacing: 2

                    Repeater {
                        model: 3

                        Rectangle {
                            id: bar

                            required property int index

                            anchors.bottom: parent.bottom
                            width: 3
                            height: 3
                            color: root.playing ? Theme.accent : Theme.muted

                            SequentialAnimation on height {
                                running: root.playing && root.visible
                                loops: Animation.Infinite
                                onRunningChanged: if (!running) bar.height = 3

                                PauseAnimation {
                                    duration: bar.index * 140
                                }
                                NumberAnimation {
                                    to: 10
                                    duration: 320
                                    easing.type: Easing.InOutSine
                                }
                                NumberAnimation {
                                    to: 3
                                    duration: 320
                                    easing.type: Easing.InOutSine
                                }
                            }
                        }
                    }
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.hasLength ? `${root.clockText(root.position)} / ${root.clockText(root.player?.length ?? 0)}` : root.playing ? "Playing" : "Paused"
                    color: Theme.muted
                }

                Item {
                    width: Metrics.gap
                    height: 1
                }

                IconButton {
                    size: 22
                    icon: "󰒮"
                    enabled: root.player?.canGoPrevious ?? false
                    onClicked: root.player?.previous()
                }

                IconButton {
                    size: 22
                    icon: root.playing ? "󰏤" : "󰐊"
                    enabled: root.player?.canTogglePlaying ?? false
                    onClicked: root.player?.togglePlaying()
                }

                IconButton {
                    size: 22
                    icon: "󰒭"
                    enabled: root.player?.canGoNext ?? false
                    onClicked: root.player?.next()
                }
            }
        }
    }
}
