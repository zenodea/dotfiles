pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.style
import qs.widgets

Item {
    id: root

    required property ShellScreen screen

    readonly property bool shown: Panels.drawer && Panels.screen?.name === screen?.name
    readonly property alias hitArea: hitArea

    y: Metrics.barHeight
    width: shown ? Metrics.drawerWidth : 0
    height: parent.height - Metrics.barHeight - Metrics.strip

    visible: width > 0
    clip: true

    Behavior on width {
        Morph {}
    }

    Item {
        id: hitArea

        width: root.shown ? Metrics.drawerWidth : 0
        height: root.height
    }

    HoverHandler {
        onHoveredChanged: Panels.drawerPointer = hovered
    }

    Column {
        width: Metrics.drawerWidth
        height: root.height

        TabBar {
            id: tabs

            width: parent.width
            current: Panels.drawerTab
            model: [
                {
                    id: "dashboard",
                    label: "Dashboard"
                },
                {
                    id: "windows",
                    label: "Windows"
                },
                {
                    id: "clipboard",
                    label: "Clipboard"
                }
            ]
            onPicked: id => Panels.drawerTab = id
        }

        Rectangle {
            width: parent.width
            height: Metrics.borderWidth
            color: Theme.alpha(Theme.fg, 0.15)
        }

        Flickable {
            width: parent.width
            height: root.height - tabs.height - Metrics.borderWidth
            contentHeight: content.implicitHeight + Metrics.drawerPadding * 2
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Loader {
                id: content

                x: Metrics.drawerPadding
                y: Metrics.drawerPadding
                width: parent.width - Metrics.drawerPadding * 2

                sourceComponent: {
                    if (Panels.drawerTab === "windows")
                        return windowsTab;
                    if (Panels.drawerTab === "clipboard")
                        return clipboardTab;
                    return dashboardTab;
                }
            }
        }
    }

    Component {
        id: dashboardTab

        Dashboard {}
    }

    Component {
        id: windowsTab

        Windows {}
    }

    Component {
        id: clipboardTab

        Clipboard {}
    }
}
