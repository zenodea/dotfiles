pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.style
import qs.widgets

Column {
    id: root

    readonly property var groups: Hyprland.workspaces.values.filter(w => w.id > 0 && (w.toplevels?.values?.length ?? 0) > 0).sort((a, b) => a.id - b.id)

    spacing: 14

    Text {
        visible: root.groups.length === 0
        text: "No open windows"
        color: Theme.muted
        font.family: Theme.fontMono
        font.pixelSize: 11
        renderType: Text.NativeRendering
    }

    Repeater {
        model: root.groups

        Section {
            id: group

            required property var modelData

            width: root.width
            title: `Workspace ${modelData.id}`

            Repeater {
                model: group.modelData.toplevels?.values ?? []

                ListRow {
                    id: row

                    required property var modelData

                    readonly property string appClass: modelData?.lastIpcObject?.class ?? ""
                    readonly property string appTitle: modelData?.lastIpcObject?.title ?? ""

                    width: group.width
                    current: modelData?.lastIpcObject?.address === Hyprland.activeToplevel?.lastIpcObject?.address

                    onActivated: {
                        Hyprland.dispatch(`focuswindow address:${row.modelData.lastIpcObject.address}`);
                        Panels.close();
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width

                        Text {
                            width: parent.width
                            text: row.appTitle || row.appClass
                            color: Theme.fg
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            renderType: Text.NativeRendering
                        }

                        Text {
                            width: parent.width
                            visible: row.appTitle !== ""
                            text: row.appClass
                            color: Theme.muted
                            font.family: Theme.fontMono
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            renderType: Text.NativeRendering
                        }
                    }
                }
            }
        }
    }
}
