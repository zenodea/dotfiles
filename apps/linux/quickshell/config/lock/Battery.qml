import QtQuick
import Quickshell.Services.UPower
import qs.style

Info {
    readonly property var battery: UPower.displayDevice
    readonly property int percent: Math.round((battery?.percentage ?? 0) <= 1 ? (battery?.percentage ?? 0) * 100 : battery.percentage)
    readonly property bool charging: battery?.state === UPowerDeviceState.Charging || battery?.state === UPowerDeviceState.FullyCharged

    visible: battery?.isLaptopBattery ?? false
    icon: charging ? "󰂄" : "󰁹"
    iconColor: charging ? Theme.green : percent <= 20 ? Theme.red : Theme.fg
    text: `${percent}%`
}
