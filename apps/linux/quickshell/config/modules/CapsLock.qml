import QtQuick
import Quickshell
import qs.services
import qs.style
import qs.widgets

BarButton {
    id: root

    shown: Locks.caps
    hoverable: false
    icon: "󰪛"
    iconColour: Theme.yellow
    title: "Caps lock"
}
