import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.style

Item {
    id: root

    property real close: 0

    readonly property real centerX: (Metrics.strip + width - Metrics.strip) / 2
    readonly property real centerY: (Metrics.barHeight + height - Metrics.strip) / 2
    readonly property real holeLeft: Metrics.strip + (centerX - Metrics.strip) * close
    readonly property real holeTop: Metrics.barHeight + (centerY - Metrics.barHeight) * close
    readonly property real holeWidth: (centerX - holeLeft) * 2
    readonly property real holeHeight: (centerY - holeTop) * 2

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
}
