pragma ComponentBehavior: Bound

import QtQuick
import qs.style
import qs.widgets

Card {
    id: root

    required property var provider
    property string name: ""
    property real now: 0

    title: provider.plan ? `${name} · ${provider.plan}` : name

    Repeater {
        model: root.provider.windows

        UsageRow {
            required property var modelData

            width: root.width - root.padding * 2
            entry: modelData
            now: root.now
        }
    }

    Label {
        visible: root.provider.note !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        text: root.provider.note
        color: Theme.muted
    }
}
