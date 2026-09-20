pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
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

    Timer {
        running: root.playing && root.visible
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.position = root.player?.position ?? 0
    }

    Row {
        id: row

        spacing: Metrics.popoutPadding

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: root.artSize
            height: root.artSize
            color: Theme.alpha(Theme.fg, 0.07)

            Text {
                anchors.centerIn: parent
                visible: cover.status !== Image.Ready
                text: "󰝚"
                color: Theme.alpha(Theme.muted, 0.8)
                font.family: Metrics.iconFont
                font.pixelSize: root.artSize / 2.4
                renderType: Text.NativeRendering
            }

            Image {
                id: cover

                anchors.fill: parent
                source: root.art
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: root.artSize * 2
                sourceSize.height: root.artSize * 2
                smooth: true
                asynchronous: true
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                text: root.player?.trackTitle ?? ""
                color: Theme.fgBright
                font.family: Theme.fontMono
                font.pixelSize: 15
                font.bold: true
                width: root.textWidth
                elide: Text.ElideRight
                renderType: Text.NativeRendering
            }

            Text {
                text: root.player?.trackArtist ?? ""
                color: Theme.muted
                font.family: Theme.fontMono
                font.pixelSize: 12
                width: root.textWidth
                elide: Text.ElideRight
                renderType: Text.NativeRendering
            }

            Text {
                text: root.player?.trackAlbum ?? ""
                color: Theme.muted
                font.family: Theme.fontMono
                font.pixelSize: 12
                width: root.textWidth
                elide: Text.ElideRight
                renderType: Text.NativeRendering
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

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.hasLength ? `${root.clockText(root.position)} / ${root.clockText(root.player?.length ?? 0)}` : "--:-- / --:--"
                    color: Theme.muted
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                    renderType: Text.NativeRendering
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
