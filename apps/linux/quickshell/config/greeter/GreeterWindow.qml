import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.style

PanelWindow {
    id: root

    property bool shown: false

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: Theme.bg
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "greeter"

    Component.onCompleted: shown = true

    GreeterContent {
        anchors.centerIn: parent
        opacity: root.shown && !Greeter.done ? 1 : 0
        scale: 0.96 + 0.04 * opacity

        Behavior on opacity {
            NumberAnimation {
                duration: Metrics.lockDuration
                easing.type: Easing.InOutCubic
            }
        }
    }
}
