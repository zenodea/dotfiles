import QtQuick

NumberAnimation {
    duration: Metrics.animDuration
    easing.type: Easing.Bezier
    easing.bezierCurve: Metrics.easeOutQuint
}
