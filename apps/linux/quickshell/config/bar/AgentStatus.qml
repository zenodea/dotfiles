import QtQuick
import qs.services
import qs.style
import qs.widgets

BarButton {
    id: root

    readonly property bool waiting: Agent.pendingApprovals > 0

    shown: waiting || Agent.busy
    icon: "󰚩"
    iconColour: waiting ? Theme.yellow : Theme.accent
    title: waiting ? `${Agent.label} is waiting for you` : `${Agent.label} is working`
    onClicked: Panels.toggleControls("agent")
}
