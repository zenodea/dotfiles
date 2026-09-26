import QtQuick
import QtQuick.Shapes
import qs.style

Shape {
    id: root

    property real span: 0

    width: span
    height: Metrics.innerShadow
    transformOrigin: Item.TopLeft
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: -1

        fillGradient: LinearGradient {
            x1: 0
            y1: 0
            x2: 0
            y2: Metrics.innerShadow

            GradientStop {
                position: 0
                color: Qt.rgba(0, 0, 0, Metrics.innerShadowOpacity)
            }

            GradientStop {
                position: 0.35
                color: Qt.rgba(0, 0, 0, Metrics.innerShadowOpacity * 0.3)
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
            x: root.span - Metrics.innerShadow
            y: Metrics.innerShadow
        }

        PathLine {
            x: Metrics.innerShadow
            y: Metrics.innerShadow
        }

        PathLine {
            x: 0
            y: 0
        }
    }
}
