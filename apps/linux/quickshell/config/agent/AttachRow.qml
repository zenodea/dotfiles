pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.style
import qs.widgets

Flow {
    id: root

    visible: Attachments.items.length > 0
    height: visible ? implicitHeight : 0
    spacing: Metrics.gap

    Repeater {
        model: Attachments.items

        PillButton {
            required property var modelData
            required property int index

            implicitHeight: 24
            icon: "󰋩"
            label: `${modelData.label}  ×`
            maxTextWidth: root.width - 60
            onClicked: Attachments.remove(index)
        }
    }
}
