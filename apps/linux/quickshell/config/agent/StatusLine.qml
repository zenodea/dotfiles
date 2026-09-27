import QtQuick
import qs.services
import qs.style
import qs.widgets

Item {
    id: root

    property string flash: ""

    signal sessionsClicked

    height: 26

    Label {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - buttons.width - 8
        elide: Text.ElideRight
        text: root.flash !== "" ? root.flash : Agent.pendingApprovals > 0 ? "waiting · ^J ^K ⏎" : !Agent.running ? "idle" : Agent.thinking ? "thinking…" : Agent.busy ? "working…" : "ready"
        color: root.flash !== "" ? Theme.accent : Agent.pendingApprovals > 0 || Agent.busy ? Theme.yellow : Theme.muted
        font.pixelSize: 12
    }

    Row {
        id: buttons

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: Agent.usage5h >= 0
            rightPadding: 6
            text: `5h ${Math.round(Agent.usage5h * 100)}%` + (Agent.usage7d >= 0 ? ` · 7d ${Math.round(Agent.usage7d * 100)}%` : "")
            color: Agent.usage5h >= 0.9 ? Theme.red : Agent.usage5h >= 0.7 ? Theme.yellow : Theme.muted
            font.pixelSize: 12
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: modelName.implicitWidth + 12
            height: 18
            color: modelArea.containsMouse ? Theme.alpha(Theme.fg, 0.1) : Theme.alpha(Theme.fg, 0.05)

            Label {
                id: modelName

                anchors.centerIn: parent
                text: Agent.model + (Agent.running && Agent.runningModel !== Agent.model ? "*" : "")
                color: Agent.model === "default" ? Theme.muted : Theme.accent
                font.pixelSize: 12
            }

            MouseArea {
                id: modelArea

                anchors.fill: parent
                hoverEnabled: true
                onClicked: Agent.cycleModel()
            }
        }

        IconButton {
            icon: "󰋚"
            size: 15
            enabled: Agent.sessions.length > 0
            onClicked: root.sessionsClicked()
        }

        IconButton {
            visible: Agent.busy
            icon: "󰓛"
            size: 15
            onClicked: Agent.abort()
        }

        IconButton {
            icon: "󰑓"
            size: 15
            enabled: Agent.messages.count > 0
            onClicked: Agent.reset()
        }
    }
}
