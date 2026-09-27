import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.services
import qs.style

// the frame's sides closing in over the pre-lock desktop, then the clock and password field
Item {
    id: root

    property string screenName: ""
    property real close: 0

    readonly property real centerX: (Metrics.strip + width - Metrics.strip) / 2
    readonly property real centerY: (Metrics.barHeight + height - Metrics.strip) / 2
    readonly property real holeLeft: Metrics.strip + (centerX - Metrics.strip) * close
    readonly property real holeTop: Metrics.barHeight + (centerY - Metrics.barHeight) * close
    readonly property real holeWidth: (centerX - holeLeft) * 2
    readonly property real holeHeight: (centerY - holeTop) * 2

    onCloseChanged: {
        if (close === 0 && !Lock.shut)
            Lock.release();
    }

    Component.onCompleted: close = Qt.binding(() => Lock.shut ? 1 : 0)

    Behavior on close {
        NumberAnimation {
            duration: Metrics.lockDuration
            easing.type: Easing.InOutCubic
        }
    }

    // the desktop as it was just before locking, so the frame closes over what was on screen
    Image {
        anchors.fill: parent
        source: root.screenName ? `file://${Lock.shotDir}/${root.screenName}.png` : ""
        cache: false
        asynchronous: false
    }

    Shape {
        anchors.fill: parent
        opacity: Math.min(1, root.close / 0.12)
        preferredRendererType: Shape.CurveRenderer

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            blurMax: Metrics.shadowBlur
            shadowColor: Qt.rgba(0, 0, 0, Metrics.shadowOpacity)
        }

        ShapePath {
            fillColor: Theme.bg
            fillRule: ShapePath.OddEvenFill
            strokeWidth: -1

            PathRectangle {
                width: root.width
                height: root.height
            }

            PathRectangle {
                x: root.holeLeft
                y: root.holeTop
                width: root.holeWidth
                height: root.holeHeight
                radius: Math.min(Metrics.frameRadius, root.holeWidth / 2, root.holeHeight / 2)
            }
        }
    }

    LockContent {
        anchors.centerIn: parent
        opacity: Math.max(0, (root.close - 0.85) / 0.15)
        scale: 0.96 + 0.04 * opacity
    }
}
