import QtQuick
import qs.services
import qs.style
import qs.widgets

Item {
    id: root

    property bool active: false
    property string overlay: ""
    property string doomed: ""
    property string renaming: ""
    property string draft: ""
    property string query: ""
    property bool stashed: false
    property string flash: ""

    readonly property bool picking: overlay === "sessions"
    readonly property bool configuring: overlay === "settings"
    readonly property bool confirming: doomed !== ""

    readonly property int lineStep: 60
    readonly property real pageStep: list.height / 2

    function say(text: string): void {
        flash = text;
        flashTimer.restart();
    }

    function submit(text: string): void {
        Agent.send(text);
        overlay = "";
        list.stick = true;
    }

    function scroll(delta: real): void {
        if (configuring)
            settings.scroll(delta);
        else
            list.scroll(delta);
    }

    function newChat(): void {
        Agent.reset();
        overlay = "";
        say("new thread");
    }

    function togglePicker(): void {
        overlay = !picking && Agent.sessions.length > 0 ? "sessions" : "";
        if (picking)
            picker.currentIndex = Math.max(Agent.sessions.findIndex(s => s.id === Agent.sessionId), 0);
    }

    function startRename(id: string): void {
        const session = id === "" ? picker.current : Agent.sessions.find(s => s.id === id);
        if (!session)
            return;
        query = composer.text;
        renaming = session.id;
        composer.setText(session.title, true);
        composer.focusInput();
    }

    function commitRename(): void {
        AgentStore.rename(renaming, composer.text);
        cancelRename();
    }

    function cancelRename(): void {
        renaming = "";
        composer.setText(query, false);
    }

    function askDelete(): void {
        doomed = picker.current?.id ?? "";
    }

    function cancelDelete(): void {
        doomed = "";
    }

    function confirmDelete(): void {
        Agent.forget(doomed);
        doomed = "";
        if (Agent.sessions.length === 0)
            overlay = "";
    }

    function toggleSettings(): void {
        overlay = configuring ? "" : "settings";
    }

    function movePicker(delta: int): void {
        picker.move(delta);
    }

    function pickSession(): void {
        picker.pickCurrent();
    }

    function dismiss(): void {
        if (confirming)
            cancelDelete();
        else if (renaming !== "")
            cancelRename();
        else if (overlay !== "")
            overlay = "";
        else
            Panels.close();
    }

    function open(): void {
        Agent.restore();
        Qt.callLater(composer.focusInput);
    }

    onOverlayChanged: {
        doomed = "";
        renaming = "";
        if (picking) {
            draft = composer.text;
            stashed = true;
            composer.setText("", false);
        } else if (stashed) {
            stashed = false;
            composer.setText(draft, false);
        }
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

    Connections {
        target: Attachments

        function onAdded(): void {
            root.say("attached");
        }

        function onFailed(why: string): void {
            root.say(why);
        }
    }

    Label {
        visible: !Agent.available && root.overlay === ""
        width: parent.width
        wrapMode: Text.WordWrap
        text: `${Agent.label} is not installed.\n\n${Agent.backend.installHint}`
        color: Theme.muted
        font.pixelSize: 13
    }

    Label {
        visible: Agent.available && Agent.messages.count === 0 && root.overlay === ""
        anchors.centerIn: list
        width: list.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: `Ask ${Agent.label} to do something on this machine.\n\n^P attach screen · ^V paste image\n^H history · ^S settings`
        color: Theme.alpha(Theme.muted, 0.7)
        font.pixelSize: 13
    }

    MessageList {
        id: list

        visible: Agent.available && root.overlay === ""
        width: parent.width
        height: queue.y - Metrics.gap
        onReturnFocus: composer.focusInput()
    }

    SessionPicker {
        id: picker

        visible: root.picking
        width: parent.width
        height: status.y - Metrics.gap
        query: root.renaming !== "" ? root.query : composer.text
        onRenaming: id => root.startRename(id)
        onPicked: id => {
            root.overlay = "";
            Agent.resume(id);
            list.stick = true;
        }
        onDoomed: id => root.doomed = id
    }

    ConfirmCard {
        visible: root.confirming && root.picking
        anchors.fill: picker
        title: "Delete this session?"
        detail: Agent.sessions.find(s => s.id === root.doomed)?.title ?? ""
        onConfirmed: root.confirmDelete()
        onCancelled: root.cancelDelete()
    }

    SettingsPage {
        id: settings

        visible: root.configuring
        width: parent.width
        height: status.y - Metrics.gap
    }

    QueueStack {
        id: queue

        visible: Agent.available && Agent.queue.count > 0
        y: status.y - height - (visible ? Metrics.gap : 0)
        width: parent.width
    }

    StatusLine {
        id: status

        y: attached.y - height - Metrics.gap
        width: parent.width
        flash: root.flash
        onSessionsClicked: root.togglePicker()
        onSettingsClicked: root.toggleSettings()
    }

    AttachRow {
        id: attached

        y: composer.y - height - (visible ? Metrics.gap : 0)
        width: parent.width
    }

    Composer {
        id: composer

        visible: Agent.available
        anchors.bottom: parent.bottom
        width: parent.width
        page: root
    }
}
