pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.style
import qs.widgets

Item {
    id: root

    property bool active: false
    property bool picking: false

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

    function togglePicker(): void {
        picking = !picking && Agent.sessions.length > 0;
        if (picking)
            sessionList.currentIndex = Math.max(Agent.sessions.findIndex(s => s.id === Agent.sessionId), 0);
    }

    function pickSession(): void {
        const session = Agent.sessions[sessionList.currentIndex];
        picking = false;
        if (session) {
            Agent.resume(session.id);
            list.stick = true;
        }
    }

    property string flash: ""

    readonly property int lineStep: 60

    function scroll(delta: real): void {
        const top = list.originY;
        const bottom = list.originY + Math.max(list.contentHeight - list.height, 0);
        list.contentY = Math.max(top, Math.min(list.contentY + delta, bottom));
        list.stick = list.contentY >= bottom - 1;
    }

    function say(text: string): void {
        flash = text;
        flashTimer.restart();
    }

    function newChat(): void {
        Agent.reset();
        picking = false;
        say("new thread");
    }

    function submit(): void {
        Agent.send(input.text);
        input.text = "";
        list.stick = true;
    }

    Timer {
        id: flashTimer

        interval: 4000
        onTriggered: root.flash = ""
    }

    onActiveChanged: {
        if (active) {
            Agent.restore();
            input.forceActiveFocus();
        }
    }

    Component.onCompleted: {
        if (active) {
            Agent.restore();
            input.forceActiveFocus();
        }
    }

    Text {
        visible: !Agent.available
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Claude Code is not installed.\n\ncurl -fsSL https://claude.ai/install.sh | bash"
        color: Theme.muted
        font.family: Theme.fontMono
        font.pixelSize: 13
        renderType: Text.NativeRendering
    }

    Text {
        visible: Agent.available && Agent.messages.count === 0 && !root.picking
        anchors.centerIn: list
        width: list.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: "Ask Claude to do something on this machine."
        color: Theme.alpha(Theme.muted, 0.7)
        font.family: Theme.fontMono
        font.pixelSize: 13
        renderType: Text.NativeRendering
    }

    ListView {
        id: list

        property bool stick: true

        visible: Agent.available && !root.picking
        width: parent.width
        height: queueBox.y - Metrics.gap
        clip: true
        spacing: 16
        boundsBehavior: Flickable.StopAtBounds
        model: Agent.messages

        onMovementEnded: stick = atYEnd
        onContentHeightChanged: {
            if (stick)
                positionViewAtEnd();
        }
        onHeightChanged: {
            if (stick)
                positionViewAtEnd();
        }

        delegate: Loader {
            id: entry

            required property string role
            required property string text
            required property string detail
            required property string phase
            required property string callId

            width: ListView.view.width
            sourceComponent: role === "user" ? userEntry : role === "tool" ? toolEntry : role === "approval" ? approvalEntry : role === "question" ? questionEntry : role === "error" ? errorEntry : assistantEntry

            Component {
                id: userEntry

                Row {
                    spacing: Metrics.gap

                    Text {
                        text: "›"
                        color: Theme.accent
                        font.family: Theme.fontMono
                        font.pixelSize: 14
                        renderType: Text.NativeRendering
                    }

                    Text {
                        width: entry.width - 14
                        wrapMode: Text.Wrap
                        text: entry.text
                        color: Theme.fgBright
                        font.family: Theme.fontMono
                        font.pixelSize: 14
                        renderType: Text.NativeRendering
                    }
                }
            }

            Component {
                id: assistantEntry

                TextEdit {
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.MarkdownText
                    text: entry.text
                    color: Theme.fg
                    selectionColor: Theme.alpha(Theme.accent, 0.35)
                    font.family: Theme.fontMono
                    font.pixelSize: 14
                    renderType: Text.NativeRendering
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }
            }

            Component {
                id: toolEntry

                Rectangle {
                    implicitHeight: 32
                    color: Theme.alpha(Theme.fg, 0.05)

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: Metrics.gap

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: entry.phase === "running" ? "󰔟" : entry.phase === "error" ? "󰅖" : "󰄬"
                            color: entry.phase === "running" ? Theme.yellow : entry.phase === "error" ? Theme.red : Theme.green
                            font.family: Metrics.iconFont
                            font.pixelSize: 14
                            renderType: Text.NativeRendering
                        }

                        Text {
                            id: toolName

                            anchors.verticalCenter: parent.verticalCenter
                            text: entry.text
                            color: Theme.accent
                            font.family: Theme.fontMono
                            font.pixelSize: 13
                            renderType: Text.NativeRendering
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - toolName.width - 40
                            elide: Text.ElideRight
                            text: entry.detail
                            color: Theme.muted
                            font.family: Theme.fontMono
                            font.pixelSize: 13
                            renderType: Text.NativeRendering
                        }
                    }
                }
            }

            Component {
                id: approvalEntry

                Rectangle {
                    id: ask

                    property int choice: 0

                    implicitHeight: approval.implicitHeight + 16
                    color: entry.phase === "pending" ? Theme.alpha(Theme.yellow, 0.1) : Theme.alpha(Theme.fg, 0.05)
                    border.width: entry.phase === "pending" ? Metrics.borderWidth : 0
                    border.color: Theme.alpha(Theme.yellow, 0.5)

                    Connections {
                        target: Agent
                        enabled: Agent.activeId === entry.callId

                        function onNavKey(delta: int): void {
                            ask.choice = Math.max(0, Math.min(1, ask.choice + delta));
                        }

                        function onEnterKey(): void {
                            Agent.decide(entry.callId, ask.choice === 0);
                        }
                    }

                    Column {
                        id: approval

                        x: 8
                        y: 8
                        width: parent.width - 16
                        spacing: Metrics.gap

                        Text {
                            text: entry.phase === "pending" ? `Allow ${entry.text}?` : `${entry.text} ${entry.phase}`
                            color: entry.phase === "denied" ? Theme.red : entry.phase === "allowed" ? Theme.green : Theme.yellow
                            font.family: Theme.fontMono
                            font.pixelSize: 13
                            renderType: Text.NativeRendering
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.WrapAnywhere
                            maximumLineCount: entry.phase === "pending" ? 8 : 2
                            elide: Text.ElideRight
                            text: entry.detail
                            color: Theme.fg
                            font.family: Theme.fontMono
                            font.pixelSize: 13
                            renderType: Text.NativeRendering
                        }

                        Row {
                            visible: entry.phase === "pending"
                            spacing: Metrics.gap

                            PillButton {
                                icon: "󰄬"
                                label: "Allow ^Y"
                                active: ask.choice === 0
                                onClicked: Agent.decide(entry.callId, true)
                            }

                            PillButton {
                                icon: "󰅖"
                                label: "Deny ^N"
                                active: ask.choice === 1
                                onClicked: Agent.decide(entry.callId, false)
                            }
                        }
                    }
                }
            }

            Component {
                id: questionEntry

                Rectangle {
                    id: card

                    readonly property var questions: {
                        try {
                            return JSON.parse(entry.detail);
                        } catch (e) {
                            return [];
                        }
                    }
                    readonly property bool pending: entry.phase === "pending"

                    property var picks: questions.map(() => [])
                    property var others: questions.map(() => "")

                    readonly property bool needsSubmit: questions.length > 1 || questions[0]?.multiSelect === true
                    readonly property var rows: {
                        const out = [];
                        questions.forEach((q, qi) => {
                            (q.options ?? []).forEach((o, oi) => out.push({
                                        q: qi,
                                        o: oi
                                    }));
                            out.push({
                                q: qi,
                                o: -1
                            });
                        });
                        if (needsSubmit)
                            out.push({
                                q: -1,
                                o: -1
                            });
                        return out;
                    }
                    readonly property bool focused: pending && Agent.activeId === entry.callId

                    property int cursor: 0
                    property int editing: -1

                    function isCursor(q: int, o: int): bool {
                        const row = rows[cursor];
                        return focused && editing === -1 && row !== undefined && row.q === q && row.o === o;
                    }

                    function jumpTo(q: int): void {
                        const i = rows.findIndex(r => r.q === q);
                        cursor = i === -1 ? rows.length - 1 : i;
                    }

                    function choose(): void {
                        const row = rows[cursor];
                        if (!row)
                            return;
                        if (row.q === -1) {
                            submit();
                        } else if (row.o === -1) {
                            editing = row.q;
                        } else {
                            const multi = questions[row.q].multiSelect;
                            toggle(row.q, questions[row.q].options[row.o].label);
                            if (!multi && pending)
                                jumpTo(row.q + 1);
                        }
                    }

                    readonly property int current: {
                        for (let i = 0; i < questions.length; i++)
                            if (picks[i].length === 0 && others[i] === "")
                                return i;
                        return -1;
                    }

                    function toggle(q: int, label: string): void {
                        const next = picks.slice();
                        if (questions[q].multiSelect)
                            next[q] = next[q].includes(label) ? next[q].filter(l => l !== label) : next[q].concat([label]);
                        else
                            next[q] = [label];
                        picks = next;
                        if (questions.length === 1 && !questions[q].multiSelect)
                            submit();
                    }

                    function submit(): void {
                        if (!pending || current !== -1)
                            return;
                        const answers = {};
                        questions.forEach((q, i) => answers[q.question] = others[i] !== "" ? picks[i].concat([others[i]]).join(", ") : picks[i].join(", "));
                        Agent.answer(entry.callId, answers);
                    }

                    implicitHeight: body.implicitHeight + 16
                    color: pending ? Theme.alpha(Theme.accent, 0.08) : Theme.alpha(Theme.fg, 0.05)
                    border.width: pending ? Metrics.borderWidth : 0
                    border.color: Theme.alpha(Theme.accent, 0.5)

                    Connections {
                        target: Agent
                        enabled: card.focused

                        function onOptionKey(number: int): void {
                            const q = card.current === -1 ? card.questions.length - 1 : card.current;
                            const option = card.questions[q]?.options?.[number - 1];
                            if (option)
                                card.toggle(q, option.label);
                        }

                        function onSubmitKey(): void {
                            card.submit();
                        }

                        function onNavKey(delta: int): void {
                            card.cursor = Math.max(0, Math.min(card.rows.length - 1, card.cursor + delta));
                        }

                        function onEnterKey(): void {
                            card.choose();
                        }
                    }

                    Column {
                        id: body

                        x: 8
                        y: 8
                        width: parent.width - 16
                        spacing: 14

                        Text {
                            visible: !card.pending
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: entry.phase === "answered" ? `󰋗 ${entry.text}` : "󰋗 skipped"
                            color: entry.phase === "answered" ? Theme.accent : Theme.muted
                            font.family: Theme.fontMono
                            font.pixelSize: 13
                            renderType: Text.NativeRendering
                        }

                        Repeater {
                            model: card.pending ? card.questions : []

                            Column {
                                id: question

                                required property var modelData
                                required property int index

                                width: body.width
                                spacing: 6

                                Text {
                                    text: (question.modelData.header ?? "").toUpperCase() + (question.modelData.multiSelect ? "  · pick any" : "")
                                    color: card.current === question.index ? Theme.accent : Theme.muted
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                    font.letterSpacing: 1
                                    renderType: Text.NativeRendering
                                }

                                Text {
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: question.modelData.question
                                    color: Theme.fgBright
                                    font.family: Theme.fontMono
                                    font.pixelSize: 14
                                    renderType: Text.NativeRendering
                                }

                                Repeater {
                                    model: question.modelData.options ?? []

                                    Rectangle {
                                        id: option

                                        required property var modelData
                                        required property int index

                                        readonly property bool picked: card.picks[question.index].includes(modelData.label)
                                        readonly property bool cursorOn: card.isCursor(question.index, index)

                                        width: question.width
                                        implicitHeight: optionText.implicitHeight + 10
                                        color: picked ? Theme.alpha(Theme.accent, 0.18) : cursorOn || optionArea.containsMouse ? Theme.alpha(Theme.fg, 0.09) : Theme.alpha(Theme.fg, 0.03)

                                        Rectangle {
                                            visible: option.cursorOn
                                            width: Metrics.borderWidth * 2
                                            height: parent.height
                                            color: Theme.accent
                                        }

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: Metrics.shortAnim
                                            }
                                        }

                                        Text {
                                            id: number

                                            x: 6
                                            y: 5
                                            text: option.index + 1
                                            color: option.picked ? Theme.accent : Theme.muted
                                            font.family: Theme.fontMono
                                            font.pixelSize: 13
                                            renderType: Text.NativeRendering
                                        }

                                        Column {
                                            id: optionText

                                            x: 22
                                            y: 5
                                            width: parent.width - 28

                                            Text {
                                                width: parent.width
                                                wrapMode: Text.Wrap
                                                text: option.modelData.label
                                                color: option.picked ? Theme.accent : Theme.fg
                                                font.family: Theme.fontMono
                                                font.pixelSize: 13
                                                renderType: Text.NativeRendering
                                            }

                                            Text {
                                                visible: text !== ""
                                                width: parent.width
                                                wrapMode: Text.Wrap
                                                text: option.modelData.description ?? ""
                                                color: Theme.muted
                                                font.family: Theme.fontMono
                                                font.pixelSize: 12
                                                renderType: Text.NativeRendering
                                            }
                                        }

                                        MouseArea {
                                            id: optionArea

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                card.cursor = card.rows.findIndex(r => r.q === question.index && r.o === option.index);
                                                card.toggle(question.index, option.modelData.label);
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    readonly property bool cursorOn: card.isCursor(question.index, -1)

                                    width: parent.width
                                    height: 32
                                    color: cursorOn || other.activeFocus ? Theme.alpha(Theme.fg, 0.09) : Theme.alpha(Theme.fg, 0.03)

                                    Rectangle {
                                        visible: parent.cursorOn || other.activeFocus
                                        width: Metrics.borderWidth * 2
                                        height: parent.height
                                        color: Theme.accent
                                    }

                                    Connections {
                                        target: card

                                        function onEditingChanged(): void {
                                            if (card.editing === question.index)
                                                other.forceActiveFocus();
                                        }
                                    }

                                    TextInput {
                                        id: other

                                        anchors.fill: parent
                                        anchors.leftMargin: 22
                                        anchors.rightMargin: 6
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: Theme.fg
                                        font.family: Theme.fontMono
                                        font.pixelSize: 13
                                        clip: true
                                        onTextChanged: {
                                            const next = card.others.slice();
                                            next[question.index] = text.trim();
                                            card.others = next;
                                        }
                                        function leave(): void {
                                            card.editing = -1;
                                            input.forceActiveFocus();
                                        }

                                        function commit(): void {
                                            leave();
                                            if (card.current === -1)
                                                card.submit();
                                            else
                                                card.jumpTo(card.current);
                                        }

                                        Keys.onReturnPressed: commit()
                                        Keys.onEnterPressed: commit()
                                        Keys.onEscapePressed: leave()

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: other.text === ""
                                            text: "Other…"
                                            color: Theme.alpha(Theme.muted, 0.7)
                                            font: other.font
                                            renderType: Text.NativeRendering
                                        }
                                    }
                                }
                            }
                        }

                        Row {
                            visible: card.pending
                            spacing: Metrics.gap

                            PillButton {
                                visible: card.needsSubmit
                                icon: "󰄬"
                                label: "Submit ^Y"
                                active: true
                                border.width: card.isCursor(-1, -1) ? Metrics.borderWidth : 0
                                border.color: Theme.accent
                                enabled: card.current === -1
                                onClicked: card.submit()
                            }

                            PillButton {
                                icon: "󰅖"
                                label: "Skip ^N"
                                onClicked: Agent.decide(entry.callId, false)
                            }
                        }
                    }
                }
            }

            Component {
                id: errorEntry

                Text {
                    wrapMode: Text.Wrap
                    text: entry.text
                    color: Theme.red
                    font.family: Theme.fontMono
                    font.pixelSize: 13
                    renderType: Text.NativeRendering
                }
            }
        }
    }

    ListView {
        id: sessionList

        visible: root.picking
        width: parent.width
        height: statusLine.y - Metrics.gap
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: root.picking ? Agent.sessions : []
        highlightMoveDuration: 0

        header: Text {
            height: 28
            text: "SESSIONS  · ^J ^K ⏎ · esc"
            color: Theme.muted
            font.family: Theme.fontMono
            font.pixelSize: 10
            font.letterSpacing: 1
            renderType: Text.NativeRendering
        }

        delegate: Rectangle {
            id: session

            required property var modelData
            required property int index

            readonly property bool current: ListView.isCurrentItem

            width: ListView.view.width
            height: 36
            color: current ? Theme.alpha(Theme.accent, 0.15) : sessionArea.containsMouse ? Theme.alpha(Theme.fg, 0.07) : "transparent"

            Rectangle {
                visible: session.current
                width: Metrics.borderWidth * 2
                height: parent.height
                color: Theme.accent
            }

            Text {
                id: when

                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: session.modelData.id === Agent.sessionId ? "open" : root.ago(session.modelData.updated)
                color: Theme.muted
                font.family: Theme.fontMono
                font.pixelSize: 12
                renderType: Text.NativeRendering
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.right: when.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: session.modelData.title
                color: session.current ? Theme.accent : Theme.fg
                font.family: Theme.fontMono
                font.pixelSize: 13
                renderType: Text.NativeRendering
            }

            MouseArea {
                id: sessionArea

                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    sessionList.currentIndex = session.index;
                    root.pickSession();
                }
            }
        }
    }

    Column {
        id: queueBox

        visible: Agent.available && Agent.queue.count > 0
        y: statusLine.y - height - (visible ? Metrics.gap : 0)
        width: parent.width
        height: visible ? implicitHeight : 0
        spacing: 2

        Text {
            height: 22
            verticalAlignment: Text.AlignVCenter
            text: `QUEUED · ${Agent.queue.count}${Agent.queue.count > 3 ? " · scroll" : ""} · ↑ edit`
            color: Theme.muted
            font.family: Theme.fontMono
            font.pixelSize: 10
            font.letterSpacing: 1
            renderType: Text.NativeRendering
        }

        ListView {
            id: queueList

            readonly property int rowHeight: 32

            width: parent.width
            height: Math.min(contentHeight, rowHeight * 3 + spacing * 2)
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: Agent.queue

            delegate: Rectangle {
                id: queued

                required property string text
                required property int index

                width: queueList.width
                height: 32
                color: queuedArea.containsMouse ? Theme.alpha(Theme.fg, 0.08) : Theme.alpha(Theme.fg, 0.04)

                Behavior on color {
                    ColorAnimation {
                        duration: Metrics.shortAnim
                    }
                }

                Rectangle {
                    width: Metrics.borderWidth * 2
                    height: parent.height
                    color: Theme.alpha(Theme.accent, 0.5)
                }

                MouseArea {
                    id: queuedArea

                    anchors.fill: parent
                    hoverEnabled: true
                }

                Text {
                    id: order

                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: queued.index + 1
                    color: Theme.muted
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                    renderType: Text.NativeRendering
                }

                Text {
                    anchors.left: order.right
                    anchors.leftMargin: 8
                    anchors.right: remove.left
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    text: queued.text.replace(/\s+/g, " ")
                    color: Theme.alpha(Theme.fg, 0.75)
                    font.family: Theme.fontMono
                    font.pixelSize: 13
                    renderType: Text.NativeRendering
                }

                IconButton {
                    id: remove

                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    visible: queuedArea.containsMouse || hovered
                    icon: "󰅖"
                    size: 13
                    onClicked: Agent.removeQueued(queued.index)

                    readonly property bool hovered: removeHover.hovered

                    HoverHandler {
                        id: removeHover
                    }
                }
            }
        }
    }

    Connections {
        target: Agent

        function onQueueReturned(text: string): void {
            input.text = input.text.trim() ? `${text}\n\n${input.text}` : text;
            input.cursorPosition = input.text.length;
            input.forceActiveFocus();
        }
    }

    Item {
        id: statusLine

        visible: Agent.available
        y: field.y - height - Metrics.gap
        width: parent.width
        height: 26

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.flash !== "" ? root.flash : Agent.pendingApprovals > 0 ? "waiting · ^J ^K ⏎" : !Agent.running ? "idle" : Agent.thinking ? "thinking…" : Agent.busy ? "working…" : "ready"
            width: parent.width - statusButtons.width - 8
            elide: Text.ElideRight
            color: root.flash !== "" ? Theme.accent : Agent.pendingApprovals > 0 || Agent.busy ? Theme.yellow : Theme.muted
            font.family: Theme.fontMono
            font.pixelSize: 12
            renderType: Text.NativeRendering
        }

        Row {
            id: statusButtons

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Agent.usage5h >= 0
                rightPadding: 6
                text: `5h ${Math.round(Agent.usage5h * 100)}%` + (Agent.usage7d >= 0 ? ` · 7d ${Math.round(Agent.usage7d * 100)}%` : "")
                color: Agent.usage5h >= 0.9 ? Theme.red : Agent.usage5h >= 0.7 ? Theme.yellow : Theme.muted
                font.family: Theme.fontMono
                font.pixelSize: 12
                renderType: Text.NativeRendering
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: modelLabel.implicitWidth + 12
                height: 18
                color: modelArea.containsMouse ? Theme.alpha(Theme.fg, 0.1) : Theme.alpha(Theme.fg, 0.05)

                Text {
                    id: modelLabel

                    anchors.centerIn: parent
                    text: Agent.model + (Agent.running && Agent.runningModel !== Agent.model ? "*" : "")
                    color: Agent.model === "default" ? Theme.muted : Theme.accent
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                    renderType: Text.NativeRendering
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
                onClicked: root.togglePicker()
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

    Rectangle {
        id: field

        visible: Agent.available
        anchors.bottom: parent.bottom
        width: parent.width
        height: Math.min(Math.max(input.contentHeight + 16, 40), 160)
        color: Theme.alpha(Theme.fg, 0.06)

        Flickable {
            id: scroller

            anchors.fill: parent
            anchors.margins: 8
            contentHeight: input.contentHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            TextEdit {
                id: input

                width: scroller.width
                wrapMode: TextEdit.Wrap
                color: Theme.fgBright
                selectionColor: Theme.alpha(Theme.accent, 0.35)
                font.family: Theme.fontMono
                font.pixelSize: 14
                renderType: Text.NativeRendering

                onCursorRectangleChanged: {
                    if (cursorRectangle.y + cursorRectangle.height > scroller.contentY + scroller.height)
                        scroller.contentY = cursorRectangle.y + cursorRectangle.height - scroller.height;
                    else if (cursorRectangle.y < scroller.contentY)
                        scroller.contentY = cursorRectangle.y;
                }

                Keys.onEscapePressed: {
                    if (root.picking)
                        root.picking = false;
                    else
                        Panels.close();
                }
                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    if (event.key === Qt.Key_Up && !ctrl && input.text === "" && Agent.queue.count > 0) {
                        input.text = Agent.popQueued();
                        input.cursorPosition = input.text.length;
                        event.accepted = true;
                        return;
                    }
                    if (ctrl && event.key === Qt.Key_O) {
                        root.togglePicker();
                        event.accepted = true;
                    } else if (root.picking && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                        root.pickSession();
                        event.accepted = true;
                    } else if (root.picking && ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_K)) {
                        sessionList.currentIndex = Math.max(0, Math.min(Agent.sessions.length - 1, sessionList.currentIndex + (event.key === Qt.Key_J ? 1 : -1)));
                        event.accepted = true;
                    } else if (ctrl && event.key === Qt.Key_M) {
                        Agent.cycleModel();
                        event.accepted = true;
                    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                        if (input.text.trim() === "" && Agent.activeId !== "")
                            Agent.enterKey();
                        else
                            root.submit();
                        event.accepted = true;
                    } else if (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_K) && Agent.activeId !== "") {
                        Agent.navKey(event.key === Qt.Key_J ? 1 : -1);
                        event.accepted = true;
                    } else if (ctrl && event.key === Qt.Key_C && input.selectedText === "") {
                        Agent.abort();
                        event.accepted = true;
                    } else if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && Agent.pendingApprovals > 0) {
                        Agent.optionKey(event.key - Qt.Key_0);
                        event.accepted = true;
                    } else if (ctrl && (event.key === Qt.Key_Y || event.key === Qt.Key_N) && Agent.pendingApprovals > 0) {
                        Agent.decideLatest(event.key === Qt.Key_Y);
                        event.accepted = true;
                    } else if (ctrl && event.key === Qt.Key_N) {
                        root.newChat();
                        event.accepted = true;
                    } else if (ctrl && event.key === Qt.Key_H) {
                        Panels.controlsTab = "controls";
                        event.accepted = true;
                    } else if (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_K)) {
                        root.scroll(event.key === Qt.Key_J ? root.lineStep : -root.lineStep);
                        event.accepted = true;
                    } else if (ctrl && (event.key === Qt.Key_D || event.key === Qt.Key_U)) {
                        root.scroll((event.key === Qt.Key_D ? 1 : -1) * list.height / 2);
                        event.accepted = true;
                    }
                }

                Text {
                    visible: input.text === ""
                    text: Agent.busy ? "Queue a follow-up…" : "Ask Claude…"
                    color: Theme.alpha(Theme.muted, 0.7)
                    font: input.font
                    renderType: Text.NativeRendering
                }
            }
        }
    }
}
