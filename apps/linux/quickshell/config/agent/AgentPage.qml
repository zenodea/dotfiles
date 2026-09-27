import QtQuick
import qs.services
import qs.style
import qs.widgets

Item {
    id: root

    property bool active: false
    property bool picking: false
    property string flash: ""

    readonly property int lineStep: 60
    readonly property real pageStep: list.height / 2

    function say(text: string): void {
        flash = text;
        flashTimer.restart();
    }

    function submit(text: string): void {
        Agent.send(text);
        list.stick = true;
    }

    function scroll(delta: real): void {
        list.scroll(delta);
    }

    function newChat(): void {
        Agent.reset();
        picking = false;
        say("new thread");
    }

    function togglePicker(): void {
        picking = !picking && Agent.sessions.length > 0;
        if (picking)
            picker.currentIndex = Math.max(Agent.sessions.findIndex(s => s.id === Agent.sessionId), 0);
    }

    function movePicker(delta: int): void {
        picker.move(delta);
    }

    function pickSession(): void {
        picker.pickCurrent();
    }

    function dismiss(): void {
        if (picking)
            picking = false;
        else
            Panels.close();
    }

    function open(): void {
        Agent.restore();
        composer.focusInput();
    }

    onActiveChanged: {
        if (active)
            open();
    }
    Component.onCompleted: {
        if (active)
            open();
    }

    Timer {
        id: flashTimer

        interval: 4000
        onTriggered: root.flash = ""
    }

    Connections {
        target: Agent

        function onQueueReturned(text: string): void {
            composer.prepend(text);
        }
    }

    Label {
        visible: !Agent.available
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Claude Code is not installed.\n\ncurl -fsSL https://claude.ai/install.sh | bash"
        color: Theme.muted
        font.pixelSize: 13
    }

    Label {
        visible: Agent.available && Agent.messages.count === 0 && !root.picking
        anchors.centerIn: list
        width: list.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: "Ask Claude to do something on this machine."
        color: Theme.alpha(Theme.muted, 0.7)
        font.pixelSize: 13
    }

    MessageList {
        id: list

        visible: Agent.available && !root.picking
        width: parent.width
        height: queue.y - Metrics.gap
        onReturnFocus: composer.focusInput()
    }

    SessionPicker {
        id: picker

        visible: root.picking
        width: parent.width
        height: status.y - Metrics.gap
        onPicked: id => {
            root.picking = false;
            Agent.resume(id);
            list.stick = true;
        }
    }

    QueueStack {
        id: queue

        visible: Agent.available && Agent.queue.count > 0
        y: status.y - height - (visible ? Metrics.gap : 0)
        width: parent.width
    }

    StatusLine {
        id: status

        visible: Agent.available
        y: composer.y - height - Metrics.gap
        width: parent.width
        flash: root.flash
        onSessionsClicked: root.togglePicker()
    }

    Composer {
        id: composer

        visible: Agent.available
        anchors.bottom: parent.bottom
        width: parent.width
        page: root
    }
}
