pragma ComponentBehavior: Bound

import QtQuick
import qs.style
import qs.widgets

Grid {
    id: root

    property var options: []
    property var disabled: []
    property string current: ""

    signal picked(string option)

    columns: Math.max(options.length, 1)
    spacing: 1

    Repeater {
        model: root.options

        PillButton {
            required property string modelData

            width: (root.width - (root.columns - 1)) / root.columns
            maxTextWidth: width - Metrics.itemPadding * 2
            label: modelData
            active: root.current === modelData
            enabled: active || !root.disabled.includes(modelData)
            onClicked: root.picked(modelData)
        }
    }
}
