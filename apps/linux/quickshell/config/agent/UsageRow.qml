import QtQuick
import qs.style
import qs.widgets

Item {
    id: root

    required property var entry
    property real now: 0

    readonly property real remaining: entry.resets > 0 ? Math.max(entry.resets - now, 0) : -1
    readonly property real elapsed: remaining >= 0 && entry.span > 0 ? Math.max(0, Math.min(1, 1 - remaining / entry.span)) : -1
    readonly property bool overPace: elapsed >= 0.1 && entry.used > elapsed
    readonly property color tone: entry.used >= 0.9 ? Theme.red : entry.used >= 0.7 || overPace ? Theme.yellow : Theme.accent

    function span(ms: real): string {
        const m = Math.ceil(ms / 60000);
        if (m < 60)
            return `${m}m`;
        if (m < 1440)
            return `${Math.floor(m / 60)}h ${m % 60}m`;
        return `${Math.floor(m / 1440)}d ${Math.floor(m % 1440 / 60)}h`;
    }

    implicitHeight: 32

    Label {
        text: root.entry.label
    }

    Label {
        anchors.right: parent.right
        text: `${Math.round(root.entry.used * 100)}%` + (root.remaining >= 0 ? ` · resets in ${root.span(root.remaining)}` : "") + (root.entry.note ? ` · ${root.entry.note}` : "")
        color: Theme.muted
        font.pixelSize: 10
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        width: parent.width
        height: 4
        color: Theme.alpha(Theme.fg, 0.14)

        Rectangle {
            width: parent.width * Math.min(root.entry.used, 1)
            height: parent.height
            color: root.tone
        }

        Rectangle {
            visible: root.elapsed >= 0
            x: Math.round((parent.width - width) * root.elapsed)
            y: -3
            width: 2
            height: parent.height + 6
            color: Theme.fgBright
        }
    }
}
