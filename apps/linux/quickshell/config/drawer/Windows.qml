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

    function addressOf(toplevel: var): string {
        const address = toplevel?.address ?? "";
        return address.startsWith("0x") ? address : `0x${address}`;
    }

    function iconFor(appClass: string): string {
        if (!appClass)
            return "";
        const entry = DesktopEntries.heuristicLookup(appClass);
        return entry?.icon ? Quickshell.iconPath(entry.icon, true) : "";
    }

    spacing: 12

    Label {
        visible: root.groups.length === 0
        text: "No open windows"
        color: Theme.muted
    }

    Repeater {
        model: root.groups

        Column {
            id: group

            required property var modelData

            readonly property var windows: group.modelData.toplevels?.values ?? []

            width: root.width
            spacing: 2

            Row {
                width: parent.width
                spacing: 6

                Label {
                    text: `WORKSPACE ${group.modelData.id}`
                    color: group.modelData.focused ? Theme.accent : Theme.muted
                    font.pixelSize: 9
                    font.letterSpacing: 1.2
                }

                Label {
                    text: group.windows.length
                    color: Theme.alpha(Theme.muted, 0.6)
                    font.pixelSize: 9
                }
            }

            Repeater {
                model: group.windows

                Rectangle {
                    id: row

                    required property HyprlandToplevel modelData

                    readonly property string appClass: modelData?.wayland?.appId || modelData?.lastIpcObject?.class || ""
                    readonly property bool active: modelData?.address === Hyprland.activeToplevel?.address

                    width: group.width
                    height: 40
                    color: active ? Theme.alpha(Theme.accent, 0.12) : rowHover.hovered ? Theme.alpha(Theme.fg, 0.07) : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: Metrics.shortAnim
                        }
                    }

                    HoverHandler {
                        id: rowHover
                    }

                    Image {
                        id: icon

                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        source: root.iconFor(row.appClass)
                        width: 20
                        height: 20
                        sourceSize.width: 40
                        sourceSize.height: 40
                        asynchronous: true
                    }

                    Column {
                        anchors.left: icon.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter

                        Label {
                            width: parent.width
                            text: row.modelData?.title || row.appClass
                            color: row.active ? Theme.accent : Theme.fg
                            elide: Text.ElideRight
                        }

                        Label {
                            width: parent.width
                            visible: row.appClass !== ""
                            text: row.appClass
                            color: Theme.muted
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            Hyprland.dispatch(`workspace ${group.modelData.id}`);
                            Hyprland.dispatch(`focuswindow address:${root.addressOf(row.modelData)}`);
                            Panels.close();
                        }
                    }
                }
            }
        }
    }
}
