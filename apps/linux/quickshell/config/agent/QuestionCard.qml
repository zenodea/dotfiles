pragma ComponentBehavior: Bound

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

    readonly property var view: ListView.view
    readonly property var questions: {
        try {
            return JSON.parse(detail);
        } catch (e) {
            return [];
        }
    }
    readonly property bool pending: phase === "pending"
    readonly property bool focused: pending && Agent.activeId === callId
    readonly property bool needsSubmit: questions.length > 1 || questions[0]?.multiSelect === true

    property var picks: questions.map(() => [])
    property var others: questions.map(() => "")
    property int cursor: 0
    property int editing: -1

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

    readonly property int current: {
        for (let i = 0; i < questions.length; i++)
            if (picks[i].length === 0 && others[i] === "")
                return i;
        return -1;
    }

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
            toggle(row.q, questions[row.q].options[row.o].label);
            if (!questions[row.q].multiSelect && pending)
                jumpTo(row.q + 1);
        }
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

    function setOther(q: int, value: string): void {
        const next = others.slice();
        next[q] = value.trim();
        others = next;
    }

    function leaveOther(): void {
        editing = -1;
        view.returnFocus();
    }

    function submit(): void {
        if (!pending || current !== -1)
            return;
        const answers = {};
        questions.forEach((q, i) => answers[q.question] = others[i] !== "" ? picks[i].concat([others[i]]).join(", ") : picks[i].join(", "));
        Agent.answer(callId, answers);
    }

    width: view.width
    implicitHeight: body.implicitHeight + 16
    color: pending ? Theme.alpha(Theme.accent, 0.08) : Theme.alpha(Theme.fg, 0.05)
    border.width: pending ? Metrics.borderWidth : 0
    border.color: Theme.alpha(Theme.accent, 0.5)

    Connections {
        target: Agent
        enabled: root.focused

        function onOptionKey(number: int): void {
            const q = root.current === -1 ? root.questions.length - 1 : root.current;
            const option = root.questions[q]?.options?.[number - 1];
            if (option)
                root.toggle(q, option.label);
        }

        function onSubmitKey(): void {
            root.submit();
        }

        function onNavKey(delta: int): void {
            root.cursor = Math.max(0, Math.min(root.rows.length - 1, root.cursor + delta));
        }

        function onEnterKey(): void {
            root.choose();
        }
    }

    Column {
        id: body

        x: 8
        y: 8
        width: parent.width - 16
        spacing: 14

        Label {
            visible: !root.pending
            width: parent.width
            wrapMode: Text.Wrap
            text: root.phase === "answered" ? `󰋗 ${root.text}` : "󰋗 skipped"
            color: root.phase === "answered" ? Theme.accent : Theme.muted
            font.pixelSize: 13
        }

        Repeater {
            model: root.pending ? root.questions : []

            Column {
                id: question

                required property var modelData
                required property int index

                width: body.width
                spacing: 6

                SectionHeader {
                    text: (question.modelData.header ?? "").toUpperCase() + (question.modelData.multiSelect ? "  · pick any" : "")
                    color: root.current === question.index ? Theme.accent : Theme.muted
                }

                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: question.modelData.question
                    color: Theme.fgBright
                    font.pixelSize: 14
                }

                Repeater {
                    model: question.modelData.options ?? []

                    OptionRow {
                        required property var modelData
                        required property int index

                        width: question.width
                        number: index + 1
                        label: modelData.label
                        description: modelData.description ?? ""
                        picked: root.picks[question.index].includes(modelData.label)
                        cursor: root.isCursor(question.index, index)
                        onClicked: {
                            root.cursor = root.rows.findIndex(r => r.q === question.index && r.o === index);
                            root.toggle(question.index, modelData.label);
                        }
                    }
                }

                Rectangle {
                    readonly property bool cursorOn: root.isCursor(question.index, -1) || other.activeFocus

                    width: parent.width
                    height: 32
                    color: cursorOn ? Theme.alpha(Theme.fg, 0.09) : Theme.alpha(Theme.fg, 0.03)

                    AccentBar {
                        visible: parent.cursorOn
                    }

                    Connections {
                        target: root

                        function onEditingChanged(): void {
                            if (root.editing === question.index)
                                other.forceActiveFocus();
                        }
                    }

                    TextInput {
                        id: other

                        function commit(): void {
                            root.leaveOther();
                            if (root.current === -1)
                                root.submit();
                            else
                                root.jumpTo(root.current);
                        }

                        anchors.fill: parent
                        anchors.leftMargin: 22
                        anchors.rightMargin: 6
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg
                        font.family: Theme.fontMono
                        font.pixelSize: 13
                        clip: true
                        onTextChanged: root.setOther(question.index, text)
                        Keys.onReturnPressed: commit()
                        Keys.onEnterPressed: commit()
                        Keys.onEscapePressed: root.leaveOther()

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: other.text === ""
                            text: "Other…"
                            color: Theme.alpha(Theme.muted, 0.7)
                            font: other.font
                        }
                    }
                }
            }
        }

        Row {
            visible: root.pending
            spacing: Metrics.gap

            PillButton {
                visible: root.needsSubmit
                icon: "󰄬"
                label: "Submit ^Y"
                active: true
                border.width: root.isCursor(-1, -1) ? Metrics.borderWidth : 0
                border.color: Theme.accent
                enabled: root.current === -1
                onClicked: root.submit()
            }

            PillButton {
                icon: "󰅖"
                label: "Skip ^N"
                onClicked: Agent.decide(root.callId, "deny")
            }
        }
    }
}
