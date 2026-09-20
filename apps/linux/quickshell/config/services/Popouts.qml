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
    property Component content: null

    property bool flashing: false

    property var source: null

    function show(item: Item, screen: var, opts: var): void {
        closeTimer.stop();
        flashTimer.stop();
        root.flashing = false;
        root.source = item;
        root.screen = screen;
        root.anchorX = item.mapToItem(null, item.width / 2, 0).x;
        root.title = opts.title ?? "";
        root.detail = opts.detail ?? "";
        root.level = opts.level ?? -1;
        root.content = opts.content ?? null;
        root.open = true;
    }

    function hold(item: Item): void {
        closeTimer.stop();
        flashTimer.stop();
        root.flashing = false;
    }

    function flash(item: Item, screen: var, opts: var): void {
        if (root.open && !root.flashing)
            return;

        show(item, screen, opts);
        root.flashing = true;
        flashTimer.restart();
    }

    function leave(): void {
        closeTimer.restart();
    }

    function stay(): void {
        closeTimer.stop();
    }

    Timer {
        id: flashTimer

        interval: 1600
        onTriggered: {
            root.flashing = false;
            root.open = false;
            root.source = null;
        }
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
