import QtQuick
import Quickshell.Wayland
import qs.style

WlSessionLockSurface {
    id: root

    color: Theme.bg

    LockScene {
        anchors.fill: parent
        screenName: root.screen?.name ?? ""
    }
}
