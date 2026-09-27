import QtQuick
import qs.style

// a strip along a screen edge that fires dwelled after the pointer rests on it
Item {
    id: root

    readonly property bool hovered: hover.hovered

    signal dwelled

    HoverHandler {
        id: hover

        onHoveredChanged: {
            if (hovered)
                dwell.restart();
            else
                dwell.stop();
        }
    }

    Timer {
        id: dwell

        interval: Metrics.edgeDwell
        onTriggered: root.dwelled()
    }
}
