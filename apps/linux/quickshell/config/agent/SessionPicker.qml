import QtQuick
import qs.services
import qs.style
import qs.widgets

ListView {
    id: root

    property string query: ""

    readonly property var shown: {
        const words = query.toLowerCase().split(/\s+/).filter(w => w !== "");
        return Agent.sessions.filter(s => words.every(w => s.title.toLowerCase().includes(w)));
    }
    readonly property var current: shown[currentIndex]

    signal picked(string id)
    signal doomed(string id)
    signal renaming(string id)

    function ago(ms: real): string {
        const m = Math.floor((Date.now() - ms) / 60000);
        if (m < 1)
            return "now";
        if (m < 60)
            return `${m}m`;
        if (m < 1440)
            return `${Math.floor(m / 60)}h`;
        return `${Math.floor(m / 1440)}d`;
    }

    function move(delta: int): void {
        currentIndex = Math.max(0, Math.min(count - 1, currentIndex + delta));
    }

    function pickCurrent(): void {
        if (current)
            picked(current.id);
    }

    clip: true
    spacing: 2
    boundsBehavior: Flickable.StopAtBounds
    model: visible ? shown : []
    highlightMoveDuration: 0

    header: SectionHeader {
        height: 28
        text: root.count === 0 ? "SESSIONS  · no matches" : "SESSIONS  · ^J ^K ⏎ · ^R rename · ^D delete"
    }

    delegate: Rectangle {
        id: session

        required property var modelData
        required property int index

        readonly property bool current: ListView.isCurrentItem

        width: ListView.view.width
        height: 36
        color: current ? Theme.alpha(Theme.accent, 0.15) : area.containsMouse ? Theme.alpha(Theme.fg, 0.07) : "transparent"

        AccentBar {
            visible: session.current
        }

        HoverHandler {
            id: hover
        }

        Label {
            id: when

            anchors.right: remove.visible ? edit.left : parent.right
            anchors.rightMargin: remove.visible ? 4 : 8
            anchors.verticalCenter: parent.verticalCenter
            text: (session.modelData.provider === "codex" ? "codex · " : "") + (session.modelData.id === Agent.sessionId ? "open" : root.ago(session.modelData.updated))
            color: Theme.muted
            font.pixelSize: 12
        }

        Label {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: when.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: session.modelData.title
            color: session.current ? Theme.accent : Theme.fg
            font.pixelSize: 13
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                root.currentIndex = session.index;
                root.pickCurrent();
            }
        }

        IconButton {
            id: edit

            anchors.right: remove.left
            anchors.verticalCenter: parent.verticalCenter
            visible: hover.hovered
            icon: "󰏫"
            size: 14
            onClicked: root.renaming(session.modelData.id)
        }

        IconButton {
            id: remove

            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            visible: hover.hovered
            icon: "󰆴"
            size: 14
            onClicked: root.doomed(session.modelData.id)
        }
    }
}
