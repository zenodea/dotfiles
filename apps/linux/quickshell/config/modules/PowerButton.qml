import QtQuick
import Quickshell
import qs.style
import qs.widgets

BarButton {
    id: root

    icon: "󰐥"
    iconColour: hovered ? Theme.red : Theme.fg

    onClicked: Quickshell.execDetached(["sh", "-c", `${Quickshell.env("HOME")}/scripts/rofi-power`])
}
