pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool covered: false
    property bool shut: false
    property var after: []

    function leave(command: var): void {
        if (covered)
            return;
        after = command;
        shut = false;
        covered = true;
        Qt.callLater(() => root.shut = true);
    }

    function closed(): void {
        if (!after.length)
            return;
        Quickshell.execDetached(after);
        after = [];
    }

    function opened(): void {
        covered = false;
    }

    FileView {
        id: marker

        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/dotfiles-session-${Quickshell.env("XDG_SESSION_ID") ?? ""}`
        blockLoading: true
        printErrors: false
    }

    Timer {
        id: reveal

        interval: 500
        onTriggered: root.shut = false
    }

    Component.onCompleted: {
        if (marker.text() !== "")
            return;
        marker.setText("open");
        shut = true;
        covered = true;
        reveal.start();
    }
}
