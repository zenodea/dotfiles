pragma ComponentBehavior: Bound

import QtQuick
import qs.style
import qs.widgets
import "fuzzy.js" as Fuzzy

Rectangle {
    id: root

    required property PaletteModel model

    readonly property alias input: input
    readonly property int headerHeight: 48
    readonly property int labelHeight: 30
    readonly property int rowHeight: 40
    readonly property int cardHeight: 96
    readonly property int footerHeight: 34
    readonly property int rows: 8
    readonly property int pad: 14
    readonly property int fullHeight: headerHeight + labelHeight + rows * rowHeight + 6 + footerHeight + Metrics.borderWidth * 4
    readonly property color line: Theme.alpha(Theme.fg, 0.15)
    readonly property var blank: ({
            title: "",
            sub: "",
            tag: "",
            image: "",
            glyph: "",
            card: false,
            swatch: null,
            face: "",
            meter: -1,
            tint: "",
            lit: false,
            indent: 0,
            mark: "",
            positions: []
        })

    readonly property var results: model.results
    readonly property var current: results[list.currentIndex] ?? null
    readonly property var actions: current ? model.actions(current) : []
    readonly property var runner: model.scope?.showing ? model.scope : null
    property bool acting: false

    signal dismissed
    signal activated(var entry, var action)

    function reset(): void {
        acting = false;
        input.text = "";
        list.currentIndex = results.length ? 0 : -1;
        list.positionViewAtBeginning();
    }

    function step(by: int): void {
        if (runner) {
            pane.scroll(by * rowHeight);
            return;
        }
        const view = acting ? menu : list;
        if (view.count)
            view.currentIndex = Math.max(0, Math.min(view.count - 1, view.currentIndex + by));
    }

    function accept(): void {
        if (runner) {
            runner.copy();
            return;
        }
        const action = actions[acting ? menu.currentIndex : 0];
        if (current && action)
            activated(current, action);
    }

    function sync(): void {
        const wanted = results.length;
        if (slots.count > wanted)
            slots.remove(wanted, slots.count - wanted);
        while (slots.count < wanted)
            slots.append({
                slot: slots.count
            });
        if (list.currentIndex >= wanted || (list.currentIndex < 0 && wanted))
            list.currentIndex = wanted ? 0 : -1;
    }

    width: 720
    height: fullHeight
    color: Theme.alpha(Theme.bg, 0.8)
    radius: Metrics.frameRadius
    border.width: Metrics.borderWidth
    border.color: line

    onResultsChanged: sync()
    onActingChanged: menu.currentIndex = 0
    Component.onCompleted: sync()

    Connections {
        target: root.model

        function onScopeChanged(): void {
            root.reset();
        }
    }

    ListModel {
        id: slots
    }

    component Key: Rectangle {
        property alias text: keyLabel.text

        width: keyLabel.implicitWidth + 12
        height: 18
        color: "transparent"
        border.width: Metrics.borderWidth
        border.color: Theme.alpha(Theme.fg, 0.25)

        Label {
            id: keyLabel

            anchors.centerIn: parent
        }
    }

    component Hint: Row {
        property alias key: hintKey.text
        property alias text: hintLabel.text

        spacing: 6

        Key {
            id: hintKey
        }

        Label {
            id: hintLabel

            anchors.verticalCenter: parent.verticalCenter
            color: Theme.muted
        }
    }

    Column {
        id: column

        x: Metrics.borderWidth
        y: Metrics.borderWidth
        width: parent.width - Metrics.borderWidth * 2

        Item {
            width: parent.width
            height: root.headerHeight

            Icon {
                x: root.pad
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{f0349}"
                color: Theme.muted
                font.pixelSize: Metrics.iconSize
            }

            Rectangle {
                id: chip

                visible: root.model.scope !== null
                x: root.pad + Metrics.iconSize + 12
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? chipLabel.implicitWidth + 16 : 0
                height: 22
                color: Theme.alpha(Theme.fg, 0.1)
                border.width: Metrics.borderWidth
                border.color: Theme.alpha(Theme.fg, 0.25)

                Label {
                    id: chipLabel

                    anchors.centerIn: parent
                    text: root.model.scope?.label ?? ""
                    color: Theme.fgBright
                }
            }

            TextInput {
                id: input

                x: chip.x + (chip.visible ? chip.width + 10 : 0)
                width: escapeKey.x - x - 12
                height: parent.height
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.fgBright
                font.family: Theme.fontMono
                font.pixelSize: 15
                selectionColor: Theme.alpha(Theme.accent, 0.35)
                selectedTextColor: Theme.fgBright
                clip: true

                onTextChanged: {
                    const target = root.model.scope ? null : root.model.prefixed(text.charAt(0));
                    if (target) {
                        root.model.scope = target;
                        return;
                    }
                    if (root.runner)
                        root.runner.dismiss();
                    root.acting = false;
                    root.model.query = text;
                    list.currentIndex = root.results.length ? 0 : -1;
                    list.positionViewAtBeginning();
                }

                Keys.onEscapePressed: {
                    if (root.acting)
                        root.acting = false;
                    else if (root.runner?.running)
                        root.runner.stop();
                    else if (root.runner)
                        root.runner.dismiss();
                    else if (root.model.scope)
                        root.model.scope = null;
                    else
                        root.dismissed();
                }
                Keys.onDownPressed: root.step(1)
                Keys.onUpPressed: root.step(-1)
                Keys.onReturnPressed: root.accept()
                Keys.onEnterPressed: root.accept()
                Keys.onTabPressed: root.acting = !root.runner && !root.acting && root.actions.length > 1
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Backspace && text === "" && root.model.scope) {
                        root.model.scope = null;
                        event.accepted = true;
                        return;
                    }
                    if (!(event.modifiers & Qt.ControlModifier))
                        return;
                    const steps = {
                        [Qt.Key_J]: 1,
                        [Qt.Key_N]: 1,
                        [Qt.Key_K]: -1,
                        [Qt.Key_P]: -1,
                        [Qt.Key_D]: root.rows,
                        [Qt.Key_U]: -root.rows
                    };
                    if (!steps[event.key])
                        return;
                    root.step(steps[event.key]);
                    event.accepted = true;
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text === ""
                    text: root.model.scope ? root.model.scope.hint ?? `Search ${root.model.scope.label.toLowerCase()}…` : "Search apps, commands, themes…"
                    color: Theme.alpha(Theme.muted, 0.7)
                    font: input.font
                }
            }

            Key {
                id: escapeKey

                x: parent.width - width - root.pad
                anchors.verticalCenter: parent.verticalCenter
                text: "Esc"
            }
        }

        Rectangle {
            width: parent.width
            height: Metrics.borderWidth
            color: root.line
        }

        Item {
            width: parent.width
            height: root.labelHeight

            Label {
                x: root.pad
                y: 10
                text: root.runner ? "OUTPUT" : root.results.length === 0 ? (root.model.scope?.live && input.text.trim().length < 2 ? "START TYPING" : "NO RESULTS") : input.text.trim() === "" ? (root.model.scope ? "RECENT" : "SUGGESTED") : "RESULTS"
                color: Theme.muted
                font.letterSpacing: 1
            }
        }

        ListView {
            id: list

            width: parent.width
            height: root.rows * root.rowHeight
            visible: !root.runner
            model: slots
            clip: true
            currentIndex: -1
            keyNavigationEnabled: false
            boundsBehavior: Flickable.StopAtBounds
            interactive: !root.acting
            highlightFollowsCurrentItem: true
            highlightMoveDuration: 60
            highlightMoveVelocity: -1
            highlightResizeDuration: 0
            highlight: Marker {}

            Momentum {}

            delegate: Item {
                id: row

                required property int index

                readonly property var entry: root.results[index] ?? root.blank
                readonly property bool selected: list.currentIndex === index

                width: list.width
                height: entry.card ? root.cardHeight : root.rowHeight

                Row {
                    visible: row.entry.card
                    anchors.centerIn: parent
                    spacing: 28

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 230)
                        text: row.entry.sub
                        color: Theme.fg
                        font.pixelSize: 22
                        elide: Text.ElideRight
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "→"
                        color: Theme.accent
                        font.pixelSize: 20
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 260)
                        text: row.entry.title
                        color: Theme.fgBright
                        font.pixelSize: 22
                        font.bold: true
                        elide: Text.ElideRight
                    }
                }

                Image {
                    id: picture

                    x: root.pad + row.entry.indent
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !row.entry.card && row.entry.image !== "" && status !== Image.Error
                    source: row.entry.image
                    width: 20
                    height: 20
                    sourceSize.width: 40
                    sourceSize.height: 40
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }

                Rectangle {
                    x: root.pad + 1 + row.entry.indent
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.entry.swatch !== null
                    width: 18
                    height: 18
                    color: row.entry.swatch?.[0] ?? "transparent"
                    border.width: Metrics.borderWidth
                    border.color: Theme.alpha(Theme.fg, 0.3)

                    Rectangle {
                        anchors.centerIn: parent
                        width: 8
                        height: 8
                        color: row.entry.swatch?.[1] ?? "transparent"
                    }
                }

                Label {
                    x: root.pad + row.entry.indent - 2
                    width: 24
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    visible: row.entry.mark !== ""
                    text: row.entry.mark
                    color: row.selected ? Theme.fgBright : Theme.fg
                    font.pixelSize: 17
                }

                Label {
                    x: root.pad + row.entry.indent
                    width: 20
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    visible: row.entry.face !== ""
                    text: "Aa"
                    color: row.selected ? Theme.fgBright : Theme.fg
                    font.family: row.entry.face || Theme.fontMono
                    font.pixelSize: 13
                }

                Icon {
                    x: root.pad + row.entry.indent
                    width: 20
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    visible: !row.entry.card && !picture.visible && row.entry.swatch === null && row.entry.face === "" && row.entry.mark === ""
                    text: row.entry.glyph ?? ""
                    color: row.selected ? Theme.fgBright : Theme.muted
                    font.pixelSize: Metrics.iconSize
                }

                Label {
                    visible: !row.entry.card
                    x: root.pad + 32 + row.entry.indent
                    width: (meter.visible ? meter.x : tag.x) - x - 12
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.StyledText
                    text: Fuzzy.marked(row.entry.title, row.entry.positions, Theme.accent) + (row.entry.sub ? `  <font color="${Theme.muted}">${Fuzzy.safe(row.entry.sub)}</font>` : "")
                    color: row.selected ? Theme.fgBright : Theme.fg
                    font.pixelSize: Metrics.fontSize
                    elide: Text.ElideRight
                }

                Label {
                    id: tag

                    x: parent.width - width - root.pad
                    y: row.entry.card ? 10 : (parent.height - height) / 2
                    text: row.entry.tag
                    color: row.entry.lit ? Theme.accent : Theme.muted
                }

                Rectangle {
                    id: meter

                    visible: !row.entry.card && row.entry.meter >= 0
                    x: parent.width - root.pad - 150
                    anchors.verticalCenter: parent.verticalCenter
                    width: 64
                    height: 4
                    color: Theme.alpha(Theme.fg, 0.15)

                    Rectangle {
                        width: Math.round(parent.width * Math.max(0, Math.min(1, row.entry.meter)))
                        height: parent.height
                        color: row.entry.tint || Theme.accent
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        list.currentIndex = row.index;
                        root.acting = false;
                        root.accept();
                    }
                }
            }
        }

        OutputPane {
            id: pane

            width: parent.width
            height: root.rows * root.rowHeight
            visible: root.runner !== null
            runner: root.runner
        }

        Item {
            width: parent.width
            height: 6
        }

        Rectangle {
            width: parent.width
            height: Metrics.borderWidth
            color: root.line
        }

        Item {
            width: parent.width
            height: root.footerHeight

            Label {
                x: root.pad
                anchors.verticalCenter: parent.verticalCenter
                visible: root.runner !== null
                text: !root.runner ? "" : root.runner.running ? "Running…" : `Exit ${root.runner.code} · ${root.runner.took.toFixed(1)}s · ${root.runner.lines} ${root.runner.lines === 1 ? "line" : "lines"}`
                color: root.runner && !root.runner.running && root.runner.code !== 0 ? Theme.red : Theme.muted
            }

            Row {
                x: parent.width - width - root.pad
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16
                visible: root.runner !== null

                Hint {
                    key: "↵"
                    text: "Copy output"
                }

                Hint {
                    key: "Esc"
                    text: root.runner?.running ? "Stop" : "Back"
                }
            }

            Row {
                x: root.pad
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16
                visible: !root.runner && !root.model.scope && input.text === ""

                Repeater {
                    model: root.model.prefixes

                    Hint {
                        required property var modelData

                        key: modelData.key
                        text: modelData.label
                    }
                }
            }

            Label {
                x: root.pad
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.runner && (root.model.scope !== null || input.text !== "")
                text: root.results.length === 1 ? "1 result" : `${root.results.length}${root.results.length >= root.model.limit ? "+" : ""} results`
                color: Theme.muted
            }

            Row {
                x: parent.width - width - root.pad
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16
                visible: root.current !== null && !root.runner

                Hint {
                    key: "↵"
                    text: root.actions[root.acting ? menu.currentIndex : 0]?.label ?? ""
                }

                Hint {
                    visible: root.actions.length > 1
                    key: "Tab"
                    text: "Actions"
                }
            }
        }
    }

    Rectangle {
        visible: root.acting
        x: parent.width - width - 10
        y: Math.max(root.headerHeight + 8, parent.height - height - root.footerHeight - 10)
        width: 300
        height: menuColumn.height + Metrics.borderWidth * 2
        color: Theme.surface
        radius: Metrics.frameRadius
        border.width: Metrics.borderWidth
        border.color: Theme.alpha(Theme.fg, 0.25)

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: menuColumn

            x: Metrics.borderWidth
            y: Metrics.borderWidth
            width: parent.width - Metrics.borderWidth * 2

            Item {
                width: parent.width
                height: root.labelHeight

                Label {
                    x: 12
                    y: 10
                    width: parent.width - 24
                    text: (root.current?.title ?? "").toUpperCase()
                    color: Theme.muted
                    font.letterSpacing: 1
                    elide: Text.ElideRight
                }
            }

            ListView {
                id: menu

                width: parent.width
                height: Math.min(count, 7) * 36
                model: root.actions
                clip: true
                keyNavigationEnabled: false
                boundsBehavior: Flickable.StopAtBounds
                highlightFollowsCurrentItem: true
                highlightMoveDuration: 60
                highlightMoveVelocity: -1
                highlightResizeDuration: 0
                highlight: Marker {}

                delegate: Item {
                    id: choice

                    required property int index
                    required property var modelData

                    width: menu.width
                    height: 36

                    Label {
                        x: 12
                        width: parent.width - 24
                        anchors.verticalCenter: parent.verticalCenter
                        text: choice.modelData.label
                        color: menu.currentIndex === choice.index ? Theme.fgBright : Theme.fg
                        font.pixelSize: Metrics.fontSize
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            menu.currentIndex = choice.index;
                            root.accept();
                        }
                    }
                }
            }
        }
    }
}
