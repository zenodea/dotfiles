pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    property string summary: ""
    property string body: ""
    property string icon: ""
    property bool active: false

    function show(summary: string, body: string, icon: string): void {
        root.summary = summary;
        root.body = body ?? "";
        root.icon = icon ?? "";
        root.active = true;
        hide.restart();
    }

    Timer {
        id: hide

        interval: 2600
        onTriggered: root.active = false
    }
}
