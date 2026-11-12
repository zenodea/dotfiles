import QtQuick
import qs.services
import qs.style

// the frame's sides closing in over the pre-lock desktop, then the clock and password field
Item {
    id: root

    property string screenName: ""
    property real close: 0

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

    Curtain {
        anchors.fill: parent
        close: root.close
    }

    LockContent {
        anchors.centerIn: parent
        opacity: Math.max(0, (root.close - 0.85) / 0.15)
        scale: 0.96 + 0.04 * opacity
    }
}
