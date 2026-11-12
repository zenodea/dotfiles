import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.style

PanelWindow {
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "curtain"

    Curtain {
        anchors.fill: parent
        close: Session.shut ? 1 : 0

        Behavior on close {
            NumberAnimation {
                duration: Metrics.lockDuration
                easing.type: Easing.InOutCubic
            }
        }

        onCloseChanged: {
            if (close === 0 && !Session.shut)
                Session.opened();
            else if (close === 1 && Session.shut)
                Session.closed();
        }
    }
}
