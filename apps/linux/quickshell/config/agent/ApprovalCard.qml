import QtQuick
import qs.services
import qs.style
import qs.widgets

Rectangle {
    id: root

    required property string text
    required property string detail
    required property string phase
    required property string callId

    readonly property bool pending: phase === "pending"
    readonly property var verdicts: Agent.lasting(callId) ? ["allow", "always", "deny"] : ["allow", "deny"]

    property int choice: 0

    width: ListView.view.width
    implicitHeight: body.implicitHeight + 16
    color: pending ? Theme.alpha(Theme.yellow, 0.1) : Theme.alpha(Theme.fg, 0.05)
    border.width: pending ? Metrics.borderWidth : 0
    border.color: Theme.alpha(Theme.yellow, 0.5)

    Connections {
        target: Agent
        enabled: Agent.activeId === root.callId

        function onNavKey(delta: int): void {
            root.choice = Math.max(0, Math.min(root.verdicts.length - 1, root.choice + delta));
        }

        function onEnterKey(): void {
            Agent.decide(root.callId, root.verdicts[root.choice]);
        }
    }

    Column {
        id: body

        x: 8
        y: 8
        width: parent.width - 16
        spacing: Metrics.gap

        Label {
            text: root.pending ? `Allow ${root.text}?` : `${root.text} ${root.phase}`
            color: root.phase === "denied" ? Theme.red : root.phase === "allowed" ? Theme.green : Theme.yellow
            font.pixelSize: 13
        }

        Label {
            width: parent.width
            wrapMode: Text.WrapAnywhere
            maximumLineCount: root.pending ? 8 : 2
            elide: Text.ElideRight
            text: root.detail
            font.pixelSize: 13
        }

        Row {
            visible: root.pending
            spacing: Metrics.gap

            PillButton {
                icon: "󰄬"
                label: "Allow ^Y"
                active: root.verdicts[root.choice] === "allow"
                onClicked: Agent.decide(root.callId, "allow")
            }

            PillButton {
                visible: root.verdicts.length > 2
                icon: "󰄭"
                label: "Always ^A"
                active: root.verdicts[root.choice] === "always"
                onClicked: Agent.decide(root.callId, "always")
            }

            PillButton {
                icon: "󰅖"
                label: "Deny ^N"
                active: root.verdicts[root.choice] === "deny"
                onClicked: Agent.decide(root.callId, "deny")
            }
        }
    }
}
