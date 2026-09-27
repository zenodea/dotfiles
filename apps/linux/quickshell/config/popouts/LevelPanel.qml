import QtQuick
import qs.services
import qs.style
import qs.widgets

Item {
    id: root

    readonly property real target: 190

    x: parent.width - width
    y: Metrics.barHeight
    width: Osd.shown && !Panels.controls ? target : 0
    height: 56

    visible: width > 0
    clip: true

    Behavior on width {
        Morph {}
    }

    Item {
        x: root.width - root.target
        width: root.target
        height: root.height

        Row {
            anchors.centerIn: parent
            spacing: 12

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                text: Osd.icon
                color: Osd.muted ? Theme.muted : Theme.accent
                font.pixelSize: 18
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5

                Label {
                    text: Osd.muted ? "muted" : `${Math.round(Osd.level * 100)}%`
                    color: Theme.fgBright
                    font.pixelSize: 14
                    font.bold: true
                }

                Rectangle {
                    width: 110
                    height: 3
                    color: Theme.alpha(Theme.fg, 0.15)

                    Rectangle {
                        width: parent.width * (Osd.muted ? 0 : Math.max(0, Math.min(1, Osd.level)))
                        height: parent.height
                        color: Theme.accent

                        Behavior on width {
                            NumberAnimation {
                                duration: Metrics.shortAnim
                            }
                        }
                    }
                }
            }
        }
    }
}
