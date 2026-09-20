import QtQuick
import qs.style

Item {
    id: root

    property string label: ""
    property string value: ""
    property real level: 0
    property color fill: Theme.accent

    implicitHeight: labelText.implicitHeight + 7

    Text {
        id: labelText

        anchors.left: parent.left
        text: root.label
        color: Theme.fg
        font.family: Theme.fontMono
        font.pixelSize: 11
        renderType: Text.NativeRendering
    }

    Text {
        anchors.right: parent.right
        text: root.value
        color: Theme.muted
        font.family: Theme.fontMono
        font.pixelSize: 11
        renderType: Text.NativeRendering
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 3
        color: Theme.alpha(Theme.fg, 0.15)

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.level))
            height: parent.height
            color: root.fill

            Behavior on width {
                NumberAnimation {
                    duration: Metrics.animDuration
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Metrics.easeOutQuint
                }
            }
        }
    }
}
