import QtQuick
import qs.style
import qs.widgets

Item {
    id: root

    property string title: ""
    property string detail: ""

    signal confirmed
    signal cancelled

    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(Theme.bg, 0.75)

        MouseArea {
            anchors.fill: parent
            onClicked: root.cancelled()
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: parent.width - 32
        implicitHeight: body.implicitHeight + 24
        color: Theme.surface
        border.width: Metrics.borderWidth
        border.color: Theme.alpha(Theme.red, 0.6)

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: body

            x: 12
            y: 12
            width: parent.width - 24
            spacing: 10

            Label {
                text: root.title
                color: Theme.fgBright
                font.pixelSize: 13
            }

            Label {
                width: parent.width
                elide: Text.ElideRight
                text: root.detail
                color: Theme.muted
                font.pixelSize: 12
            }

            Row {
                spacing: Metrics.gap

                PillButton {
                    icon: "󰆴"
                    label: "Delete ⏎"
                    active: true
                    onClicked: root.confirmed()
                }

                PillButton {
                    icon: "󰅖"
                    label: "Cancel esc"
                    onClicked: root.cancelled()
                }
            }
        }
    }
}
