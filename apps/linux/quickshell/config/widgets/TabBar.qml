pragma ComponentBehavior: Bound

import QtQuick
import qs.style

Row {
    id: tabs

    property var model: []
    property string current: ""

    signal picked(string id)

    height: 38

    Repeater {
        model: tabs.model

        Rectangle {
            id: tab

            required property var modelData

            readonly property bool active: tabs.current === modelData.id

            width: tabs.width / tabs.model.length
            height: tabs.height
            color: tabArea.containsMouse && !active ? Theme.alpha(Theme.fg, 0.07) : "transparent"

            Label {
                anchors.centerIn: parent
                text: tab.modelData.label
                color: tab.active ? Theme.accent : Theme.muted

                Behavior on color {
                    ColorAnimation {
                        duration: Metrics.shortAnim
                    }
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Metrics.borderWidth * 2
                color: Theme.accent
                visible: tab.active
            }

            MouseArea {
                id: tabArea

                anchors.fill: parent
                hoverEnabled: true
                onClicked: tabs.picked(tab.modelData.id)
            }
        }
    }
}
