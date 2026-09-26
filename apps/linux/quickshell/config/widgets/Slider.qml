import QtQuick
import qs.style

Item {
    id: root

    property real value: 0
    property color fill: Theme.accent
    property bool enabled: true

    signal moved(real value)

    implicitHeight: 18

    function apply(x: real): void {
        if (root.enabled)
            root.moved(Math.max(0, Math.min(1, x / width)));
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        color: Theme.alpha(Theme.fg, 0.15)

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.value))
            height: parent.height
            color: root.enabled ? root.fill : Theme.muted

            Behavior on width {
                Ease {
                    duration: Metrics.shortAnim
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onPressed: mouse => root.apply(mouse.x)
        onPositionChanged: mouse => {
            if (pressed)
                root.apply(mouse.x);
        }
    }
}
