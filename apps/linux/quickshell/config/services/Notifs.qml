pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    property Notification latest: null
    property bool toastShown: false
    property bool dnd: false

    readonly property var all: server.trackedNotifications.values
    readonly property int count: all.length

    function dismissAll(): void {
        for (const n of all.slice())
            n.dismiss();
    }

    function hideToast(): void {
        toastShown = false;
        toastTimer.stop();
    }

    NotificationServer {
        id: server

        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            root.latest = n;
            if (root.dnd && n.urgency !== NotificationUrgency.Critical)
                return;
            root.toastShown = true;

            const timeout = n.expireTimeout > 0 ? n.expireTimeout : 5000;
            toastTimer.interval = n.urgency === NotificationUrgency.Critical ? 12000 : timeout;
            toastTimer.restart();
        }
    }

    Timer {
        id: toastTimer

        interval: 5000
        onTriggered: root.toastShown = false
    }
}
