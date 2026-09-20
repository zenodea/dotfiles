pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.style
import qs.widgets

Column {
    id: root

    property var entries: []

    readonly property bool available: Tools.has("cliphist") && Tools.has("wl-copy")

    function refresh(): void {
        if (available)
            lister.running = true;
    }

    function copy(entry: var): void {
        Quickshell.execDetached(["sh", "-c", `cliphist decode '${entry.id}' | wl-copy`]);
        Panels.close();
    }

    spacing: 2

    Component.onCompleted: refresh()

    Process {
        id: lister

        command: ["cliphist", "list"]

        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    if (!line)
                        continue;
                    const tab = line.indexOf("\t");
                    if (tab < 0)
                        continue;
                    out.push({
                        id: line.slice(0, tab),
                        preview: line.slice(tab + 1)
                    });
                }
                root.entries = out;
            }
        }
    }

    Text {
        visible: !root.available
        width: parent.width
        wrapMode: Text.WordWrap
        text: "cliphist and wl-clipboard are not installed.\n\nsudo pacman -S cliphist wl-clipboard"
        color: Theme.muted
        font.family: Theme.fontMono
        font.pixelSize: 11
        renderType: Text.NativeRendering
    }

    Text {
        visible: root.available && root.entries.length === 0
        text: "Clipboard history is empty"
        color: Theme.muted
        font.family: Theme.fontMono
        font.pixelSize: 11
        renderType: Text.NativeRendering
    }

    Repeater {
        model: root.entries

        ListRow {
            id: entry

            required property var modelData

            width: root.width
            implicitHeight: 30
            onActivated: root.copy(entry.modelData)

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                text: entry.modelData.preview
                color: Theme.fg
                font.family: Theme.fontMono
                font.pixelSize: 11
                elide: Text.ElideRight
                renderType: Text.NativeRendering
            }
        }
    }
}
