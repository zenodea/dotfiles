pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.style

Item {
    id: root

    property int artSize: 64
    property int textWidth: 240

    readonly property MprisPlayer player: {
        const players = Mpris.players.values;
        return players.find(p => p.isPlaying) ?? players[0] ?? null;
    }

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

        Image {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.art !== ""
            source: root.art
            width: root.artSize
            height: root.artSize
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: root.artSize * 2
            sourceSize.height: root.artSize * 2
            smooth: true
            asynchronous: true
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                text: root.player?.trackTitle ?? ""
                color: Theme.fgBright
                font.family: Theme.fontMono
                font.pixelSize: 12
                font.bold: true
                width: Math.min(implicitWidth, root.textWidth)
                elide: Text.ElideRight
                renderType: Text.NativeRendering
            }

            Text {
                text: root.player?.trackArtist ?? ""
                visible: text !== ""
                color: Theme.muted
                font.family: Theme.fontMono
                font.pixelSize: 11
                width: Math.min(implicitWidth, root.textWidth)
                elide: Text.ElideRight
                renderType: Text.NativeRendering
            }

            Text {
                text: root.player?.trackAlbum ?? ""
                visible: text !== ""
                color: Theme.muted
                font.family: Theme.fontMono
                font.pixelSize: 11
                width: Math.min(implicitWidth, root.textWidth)
                elide: Text.ElideRight
                renderType: Text.NativeRendering
            }

            Item {
                width: 1
                height: 4
            }

            Rectangle {
                visible: root.hasLength
                width: root.textWidth - 40
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

            Item {
                width: 1
                height: 2
            }

            Row {
                spacing: Metrics.gap

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.hasLength
                    text: `${root.clockText(root.position)} / ${root.clockText(root.player?.length ?? 0)}`
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
