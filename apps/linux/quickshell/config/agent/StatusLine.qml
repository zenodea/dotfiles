import QtQuick
import qs.services
import qs.style
import qs.widgets

Item {
    id: root

    property string flash: ""

    signal sessionsClicked
    signal settingsClicked

    height: 26

    Label {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - buttons.width - 8
        elide: Text.ElideRight
        text: root.flash !== "" ? root.flash : !Agent.available ? "" : Agent.pendingApprovals > 0 ? "waiting · ^J ^K ⏎" : !Agent.running ? "idle" : Agent.thinking ? "thinking…" : Agent.busy ? "working…" : "ready"
        color: root.flash !== "" ? Theme.accent : Agent.pendingApprovals > 0 || Agent.busy ? Theme.yellow : Theme.muted
        font.pixelSize: 12
    }

    Row {
        id: buttons

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: modelName.implicitWidth + 12
            height: 18
            color: modelArea.containsMouse ? Theme.alpha(Theme.fg, 0.1) : Theme.alpha(Theme.fg, 0.05)

            Label {
                id: modelName

                anchors.centerIn: parent
                text: [Agent.provider, Agent.model, Agent.effort].filter((part, i) => i === 0 || part !== "default").join(" · ") + (Agent.running && Agent.stale ? "*" : "")
                color: Theme.accent
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
            visible: Agent.available
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
            visible: Agent.available
            icon: "󰑓"
            size: 15
            enabled: Agent.messages.count > 0
            onClicked: Agent.reset()
        }

        IconButton {
            icon: "󰒓"
            size: 15
            onClicked: root.settingsClicked()
        }
    }
}
