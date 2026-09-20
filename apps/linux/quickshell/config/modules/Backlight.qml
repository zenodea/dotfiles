import QtQuick
import Quickshell
import qs.style
import qs.services
import qs.widgets

BarButton {
    id: root

    readonly property var ramp: ["󰃞", "󰃟", "󰃠"]

    shown: Brightness.available
    icon: ramp[Math.min(ramp.length - 1, Math.floor(Brightness.percent / 100 * ramp.length))]
    labelWidth: 34
    label: `${Brightness.percent}%`

    level: Brightness.percent / 100
    title: `Brightness ${Brightness.percent}%`
    detail: Brightness.device

    onScrolled: delta => Brightness.set(Brightness.percent + (delta > 0 ? 5 : -5))
}
