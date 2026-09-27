import QtQuick
import qs.style

Item {
    id: root

    property string icon: ""
    property string label: ""
    property bool checked: false

    signal toggled

    property real progress: checked ? 1 : 0

    implicitHeight: 34

    Behavior on progress {
        Morph {
            duration: Metrics.animDuration
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -6
        anchors.rightMargin: -6
        color: area.containsMouse && root.enabled ? Theme.alpha(Theme.fg, 0.05) : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Metrics.shortAnim
            }
        }
    }

    Icon {
        id: glyph

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon
        color: !root.enabled ? Theme.alpha(Theme.muted, 0.4) : root.checked ? Theme.accent : Theme.muted
        font.pixelSize: 15

        Behavior on color {
            ColorAnimation {
                duration: Metrics.animDuration
            }
        }
    }

    Label {
        anchors.left: glyph.right
        anchors.leftMargin: 10
        anchors.right: track.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: !root.enabled ? Theme.alpha(Theme.muted, 0.4) : root.checked ? Theme.fgBright : Theme.fg
        elide: Text.ElideRight

        Behavior on color {
            ColorAnimation {
                duration: Metrics.animDuration
            }
        }
    }

    Rectangle {
        id: track

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 42
        height: 20
        clip: true
        color: !root.enabled ? Theme.alpha(Theme.fg, 0.08) : root.checked ? Theme.alpha(Theme.accent, 0.28) : Theme.alpha(Theme.fg, 0.12)

        Behavior on color {
            ColorAnimation {
                duration: Metrics.animDuration
            }
        }

        Rectangle {
            y: 3
            x: 3 + (track.width - 6 - width) * root.progress
            width: area.pressed && root.enabled ? 20 : 14
            height: 14
            color: !root.enabled ? Theme.alpha(Theme.muted, 0.5) : root.checked ? Theme.accent : Theme.muted

            Behavior on width {
                Ease {
                    duration: Metrics.shortAnim
                }
            }

            Behavior on color {
                ColorAnimation {
                    duration: Metrics.animDuration
                }
            }
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.toggled()
    }
}
