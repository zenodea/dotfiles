import QtQuick
import QtQuick.Shapes
import qs.style

Shape {
    id: root

    property real span: 0
    property real depth: Metrics.innerShadow
    property real strength: Metrics.innerShadowOpacity

    width: span
    height: depth
    transformOrigin: Item.TopLeft
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: -1

        fillGradient: LinearGradient {
            x1: 0
            y1: 0
            x2: 0
            y2: root.depth

            GradientStop {
                position: 0
                color: Qt.rgba(0, 0, 0, root.strength)
            }

            GradientStop {
                position: 0.35
                color: Qt.rgba(0, 0, 0, root.strength * 0.3)
            }

            GradientStop {
                position: 1
                color: Qt.rgba(0, 0, 0, 0)
            }
        }

        startX: 0
        startY: 0

        PathLine {
            x: root.span
            y: 0
        }

        PathLine {
            x: root.span - root.depth
            y: root.depth
        }

        PathLine {
            x: root.depth
            y: root.depth
        }

        PathLine {
            x: 0
            y: 0
        }
    }
}
