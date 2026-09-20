import QtQuick
import QtQuick.Shapes
import qs.style

Shape {
    id: root

    property real size: Metrics.frameRadius
    property color colour: Theme.bg

    width: size
    height: size
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: -1
        fillColor: root.colour
        startX: 0
        startY: 0

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
            x: 0
            y: 0
        }
    }
}
