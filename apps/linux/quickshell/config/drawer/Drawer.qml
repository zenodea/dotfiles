pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.style

Item {
    id: root

    required property ShellScreen screen

    readonly property bool shown: Panels.drawer && Panels.screen?.name === screen?.name
    readonly property alias hitArea: hitArea

    x: 0
    y: Metrics.barHeight
    width: shown ? Metrics.drawerWidth : 0
    height: parent.height - Metrics.barHeight - Metrics.strip

    visible: width > 0
    clip: true

    Behavior on width {
        NumberAnimation {
            duration: Metrics.morphDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: Metrics.emphasized
        }
    }

    Item {
        id: hitArea

        x: 0
        width: root.shown ? Metrics.drawerWidth : 0
        height: root.height
    }

    HoverHandler {
        onHoveredChanged: Panels.drawerPointer = hovered
    }

    Column {
        x: 0
        width: Metrics.drawerWidth
        height: root.height

        Row {
            id: tabs

            width: parent.width
            height: 38

            Repeater {
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

                Rectangle {
                    id: tab

                    required property var modelData

                    readonly property bool active: Panels.drawerTab === modelData.id

                    width: tabs.width / 3
                    height: tabs.height
                    color: tabArea.containsMouse && !active ? Theme.alpha(Theme.fg, 0.07) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: tab.modelData.label
                        color: tab.active ? Theme.accent : Theme.muted
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        renderType: Text.NativeRendering

                        Behavior on color {
                            ColorAnimation {
                                duration: Metrics.shortAnim
                            }
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Metrics.borderWidth * 2
                        color: Theme.accent
                        visible: tab.active
                    }

                    MouseArea {
                        id: tabArea

                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: Panels.drawerTab = tab.modelData.id
                    }
                }
            }
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
