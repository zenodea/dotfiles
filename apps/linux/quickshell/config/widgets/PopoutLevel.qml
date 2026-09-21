import QtQuick
import qs.style

Rectangle {
    id: root

    property real level: 0

    width: Metrics.popoutMinWidth - Metrics.popoutPadding * 2
    height: 3
    color: Theme.alpha(Theme.fg, 0.15)

    Rectangle {
        width: parent.width * Math.max(0, Math.min(1, root.level))
        height: parent.height
        color: Theme.accent

        Behavior on width {
            Ease {
                duration: Metrics.shortAnim
            }
        }
    }
}
