pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.UPower
import qs.services
import qs.widgets

Column {
    id: root

    visible: UPower.displayDevice?.isLaptopBattery ?? false
    spacing: 6

    PopoutRow {
        width: parent.width
        label: "Charge limit"
        value: !Charge.usable ? "" : Charge.capped ? `${Charge.limit}%` : "off"
    }

    Row {
        id: presets

        width: parent.width
        spacing: 1

        readonly property real cell: (width - (Charge.presets.length - 1)) / Charge.presets.length

        Repeater {
            model: Charge.presets

            PillButton {
                required property int modelData

                width: presets.cell
                label: modelData >= 100 ? "Full" : `${modelData}%`
                active: Charge.limit === modelData
                enabled: Charge.usable
                onClicked: Charge.set(modelData)
            }
        }
    }
}
