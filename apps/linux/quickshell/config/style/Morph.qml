import QtQuick

NumberAnimation {
    duration: Metrics.morphDuration
    easing.type: Easing.Bezier
    easing.bezierCurve: Metrics.emphasized
}
