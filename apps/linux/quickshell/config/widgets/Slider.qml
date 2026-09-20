import QtQuick
import qs.style

Item {
    id: root

    property real value: 0
    property color fill: Theme.accent

    signal moved(real value)

    implicitHeight: 18

    function apply(x: real): void {
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
            color: root.fill

            Behavior on width {
                NumberAnimation {
                    duration: Metrics.shortAnim
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Metrics.easeOutQuint
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
