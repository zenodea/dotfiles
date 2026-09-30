pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.style
import qs.widgets

Flickable {
    id: root

    property real now: Date.now()

    readonly property var servers: Agent.provider === "codex" ? AgentInfo.codexServers : AgentInfo.claudeServers

    function scroll(delta: real): void {
        contentY = Math.max(0, Math.min(contentY + delta, Math.max(contentHeight - height, 0)));
    }

    function sync(): void {
        now = Date.now();
        AgentInfo.refresh();
    }

    clip: true
    contentHeight: cards.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    onVisibleChanged: {
        if (visible)
            sync();
    }

    Timer {
        running: root.visible
        repeat: true
        interval: 30000
        onTriggered: root.sync()
    }

    Column {
        id: cards

        width: root.width
        spacing: 12

        SectionHeader {
            height: 16
            text: "SETTINGS  · ^S · esc"
        }

        Card {
            width: parent.width
            title: "Agent"

            PillGrid {
                width: parent.width
                options: Agent.providers
                disabled: Agent.busy || Agent.pendingApprovals > 0 ? Agent.providers : Agent.providers.filter(p => !Agent.backends[p].available)
                current: Agent.provider
                onPicked: option => Agent.setProvider(option)
            }

            SectionHeader {
                topPadding: 4
                text: "MODEL"
            }

            PillGrid {
                width: parent.width
                columns: Agent.models.length > 4 ? 2 : Agent.models.length
                options: Agent.models
                current: Agent.model
                onPicked: option => Agent.setModel(option)
            }

            SectionHeader {
                topPadding: 4
                text: "EFFORT"
            }

            PillGrid {
                width: parent.width
                columns: Agent.efforts.length > 4 ? Math.ceil(Agent.efforts.length / 2) : Agent.efforts.length
                options: Agent.efforts
                current: Agent.effort
                onPicked: option => Agent.setEffort(option)
            }

            SectionHeader {
                topPadding: 4
                text: "PERMISSIONS"
            }

            PillGrid {
                width: parent.width
                options: Agent.modes.map(m => m.id)
                current: Agent.mode
                onPicked: option => Agent.setMode(option)
            }

            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                text: Agent.modeNote || (Agent.modes.find(m => m.id === Agent.mode)?.hint ?? "")
                color: Agent.modeNote !== "" ? Theme.yellow : Theme.muted
            }
        }

        Card {
            width: parent.width
            title: "Thread"

            UsageRow {
                visible: Agent.contextUsed >= 0 && Agent.contextMax > 0
                width: parent.width
                entry: ({
                        label: "context",
                        used: Agent.contextMax > 0 ? Agent.contextUsed / Agent.contextMax : 0,
                        note: `${Agent.count(Agent.contextUsed)} / ${Agent.count(Agent.contextMax)}`
                    })
            }

            Label {
                visible: text !== ""
                text: Agent.spend || (Agent.contextUsed >= 0 ? "" : "no figures yet · they arrive with the next reply")
                color: Theme.muted
            }
        }

        Card {
            id: mcp

            width: parent.width
            title: "MCP servers"

            Repeater {
                model: root.servers

                Item {
                    id: server

                    required property var modelData

                    width: mcp.width - mcp.padding * 2
                    implicitHeight: 18

                    Label {
                        anchors.left: parent.left
                        anchors.right: badge.left
                        anchors.rightMargin: 8
                        elide: Text.ElideRight
                        text: server.modelData.name
                    }

                    Label {
                        id: badge

                        anchors.right: parent.right
                        text: server.modelData.status
                        color: server.modelData.tone === "ok" ? Theme.green : server.modelData.tone === "warn" ? Theme.yellow : Theme.red
                        font.pixelSize: 10
                    }
                }
            }

            Label {
                visible: root.servers.length === 0
                text: "none found"
                color: Theme.muted
            }
        }

        UsageCard {
            width: parent.width
            name: "Claude Code"
            provider: AgentInfo.claude
            now: root.now
        }

        UsageCard {
            width: parent.width
            name: "Codex"
            provider: AgentInfo.codex
            now: root.now
        }
    }
}
