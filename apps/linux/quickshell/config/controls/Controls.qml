import QtQuick
import Quickshell
import qs.services
import qs.style
import qs.widgets

Item {
    id: root

    required property ShellScreen screen

    readonly property bool shown: Panels.controls && Panels.screen?.name === screen?.name
    readonly property alias hitArea: hitArea

    x: parent.width - width
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

        x: root.width - width
        width: root.shown ? Metrics.drawerWidth : 0
        height: root.height
    }

    HoverHandler {
        onHoveredChanged: Panels.controlsPointer = hovered
    }

    Column {
        x: root.width - width
        width: Metrics.drawerWidth
        height: root.height

        TabBar {
            id: tabs

            width: parent.width
            current: Panels.controlsTab
            model: [
                {
                    id: "controls",
                    label: "Controls"
                },
                {
                    id: "agent",
                    label: "Agent"
                }
            ]
            onPicked: id => Panels.controlsTab = id
        }

        Rectangle {
            width: parent.width
            height: Metrics.borderWidth
            color: Theme.alpha(Theme.fg, 0.15)
        }

        Loader {
            width: parent.width
            height: root.height - tabs.height - Metrics.borderWidth
            sourceComponent: Panels.controlsTab === "agent" ? agentTab : controlsTab
        }
    }

    Component {
        id: agentTab

        Item {
            AgentChat {
                x: Metrics.drawerPadding
                y: Metrics.drawerPadding
                width: parent.width - Metrics.drawerPadding * 2
                height: parent.height - Metrics.drawerPadding * 2
                active: root.shown
            }
        }
    }

    Component {
        id: controlsTab

        Flickable {
            contentHeight: cards.implicitHeight + Metrics.drawerPadding * 2
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: cards

                x: Metrics.drawerPadding
                y: Metrics.drawerPadding
                width: parent.width - Metrics.drawerPadding * 2
                spacing: 12

                Card {
                    width: parent.width
                    title: "Levels"

                    Levels {
                        width: parent.width
                    }
                }

                Card {
                    width: parent.width
                    title: "Network"

                    WifiPicker {
                        width: parent.width
                        scanning: root.shown
                    }

                    BluetoothPicker {
                        width: parent.width
                    }

                    VpnPicker {
                        width: parent.width
                    }
                }

                Card {
                    width: parent.width
                    title: "Audio"

                    AudioPicker {
                        width: parent.width
                    }
                }

                Card {
                    width: parent.width
                    title: "Power"

                    Profiles {
                        width: parent.width
                    }

                    ChargeLimit {
                        width: parent.width
                    }

                    Toggle {
                        width: parent.width
                        enabled: Idle.available
                        icon: Idle.inhibited ? "󰅶" : "󰾪"
                        label: "Keep awake"
                        checked: Idle.inhibited
                        onToggled: Idle.toggle()
                    }

                    Toggle {
                        width: parent.width
                        enabled: Night.available
                        icon: Night.on ? "󰖔" : "󰖙"
                        label: "Night mode"
                        checked: Night.on
                        onToggled: Night.toggle()
                    }
                }

                Card {
                    width: parent.width
                    title: "Capture"

                    Capture {
                        width: parent.width
                    }
                }

                Card {
                    width: parent.width
                    title: "Tray"
                    visible: Tray.items.length > 0

                    TrayRow {
                        width: parent.width
                    }
                }
            }
        }
    }
}
