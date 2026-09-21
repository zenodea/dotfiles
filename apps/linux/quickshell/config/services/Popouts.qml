pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    property bool open: false
    property real anchorX: 0
    property var screen: null

    property string title: ""
    property string detail: ""
    property real level: -1
    property real fixedWidth: 0
    property var content: null

    property var source: null

    function show(item: Item, screen: var, opts: var): void {
        if (Panels.anyOpen)
            return;

        closeTimer.stop();
        root.source = item;
        root.screen = screen;
        root.anchorX = item.mapToItem(null, item.width / 2, 0).x;
        root.title = opts.title ?? "";
        root.detail = opts.detail ?? "";
        root.level = opts.level ?? -1;
        root.fixedWidth = opts.fixedWidth ?? 0;
        root.content = opts.content ?? null;
        root.open = true;
    }

    function leave(): void {
        closeTimer.restart();
    }

    function stay(): void {
        closeTimer.stop();
    }

    Connections {
        function onAnyOpenChanged(): void {
            if (Panels.anyOpen) {
                closeTimer.stop();
                root.open = false;
                root.source = null;
            }
        }

        target: Panels
    }

    Timer {
        id: closeTimer

        interval: 120
        onTriggered: {
            root.open = false;
            root.source = null;
        }
    }
}
