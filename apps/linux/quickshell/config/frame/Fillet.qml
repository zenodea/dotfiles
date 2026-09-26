import QtQuick
import QtQuick.Shapes
import qs.style

Shape {
    id: root

    property real size: Metrics.frameRadius
    // Bleeds under the surfaces it joins, so fractional-pixel edges can't leave a seam.
    readonly property real bleed: 1

    width: size
    height: size
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: -1
        fillColor: Theme.bg
        startX: -root.bleed
        startY: -root.bleed

        PathLine {
            x: root.size
            y: -root.bleed
        }

        PathLine {
            x: root.size
            y: 0
        }

        PathArc {
            x: 0
            y: root.size
            radiusX: root.size
            radiusY: root.size
            direction: PathArc.Counterclockwise
        }

        PathLine {
            x: -root.bleed
            y: root.size
        }

        PathLine {
            x: -root.bleed
            y: -root.bleed
        }
    }
}
