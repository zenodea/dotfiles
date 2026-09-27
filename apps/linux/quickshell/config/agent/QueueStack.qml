import QtQuick
import qs.services
import qs.style
import qs.widgets

Column {
    id: root

    readonly property int rowHeight: 32
    readonly property int maxRows: 3

    visible: Agent.queue.count > 0
    height: visible ? implicitHeight : 0
    spacing: 2

    SectionHeader {
        height: 22
        verticalAlignment: Text.AlignVCenter
        text: `QUEUED · ${Agent.queue.count}${Agent.queue.count > root.maxRows ? " · scroll" : ""} · ↑ edit`
    }

    ListView {
        id: list

        width: parent.width
        height: Math.min(contentHeight, root.rowHeight * root.maxRows + spacing * (root.maxRows - 1))
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: Agent.queue

        delegate: Rectangle {
            id: queued

            required property string text
            required property int index

            width: list.width
            height: root.rowHeight
            color: area.containsMouse ? Theme.alpha(Theme.fg, 0.08) : Theme.alpha(Theme.fg, 0.04)

            Behavior on color {
                ColorAnimation {
                    duration: Metrics.shortAnim
                }
            }

            AccentBar {
                color: Theme.alpha(Theme.accent, 0.5)
            }

            MouseArea {
                id: area

                anchors.fill: parent
                hoverEnabled: true
            }

            Label {
                id: order

                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: queued.index + 1
                color: Theme.muted
                font.pixelSize: 12
            }

            Label {
                anchors.left: order.right
                anchors.leftMargin: 8
                anchors.right: remove.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                text: queued.text.replace(/\s+/g, " ")
                color: Theme.alpha(Theme.fg, 0.75)
                font.pixelSize: 13
            }

            IconButton {
                id: remove

                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                visible: area.containsMouse || removeHover.hovered
                icon: "󰅖"
                size: 13
                onClicked: Agent.removeQueued(queued.index)

                HoverHandler {
                    id: removeHover
                }
            }
        }
    }
}
