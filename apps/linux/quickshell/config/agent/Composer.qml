import QtQuick
import qs.services
import qs.style
import qs.widgets

Rectangle {
    id: root

    required property Item page

    property alias text: input.text

    function focusInput(): void {
        input.forceActiveFocus();
    }

    function setText(text: string, select: bool): void {
        input.text = text;
        if (select)
            input.selectAll();
        else
            input.cursorPosition = text.length;
    }

    function prepend(text: string): void {
        input.text = input.text.trim() ? `${text}\n\n${input.text}` : text;
        input.cursorPosition = input.text.length;
        input.forceActiveFocus();
    }

    function handleKey(event: var): bool {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const enter = (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier);
        const vertical = event.key === Qt.Key_J || event.key === Qt.Key_K;
        const down = event.key === Qt.Key_J ? 1 : -1;
        const arrow = event.key === Qt.Key_Up || event.key === Qt.Key_Down;

        if (root.page.renaming !== "") {
            if (!enter)
                return false;
            root.page.commitRename();
        } else if (ctrl && event.key === Qt.Key_V) {
            Attachments.clipboard();
            return false;
        } else if (root.page.confirming) {
            if (enter || (ctrl && event.key === Qt.Key_Y))
                root.page.confirmDelete();
            else if (event.key === Qt.Key_Escape || (ctrl && event.key === Qt.Key_N))
                root.page.cancelDelete();
        } else if (root.page.picking && !ctrl && arrow) {
            root.page.movePicker(event.key === Qt.Key_Down ? 1 : -1);
        } else if (event.key === Qt.Key_Backspace && input.text === "" && !root.page.picking && Attachments.items.length > 0) {
            Attachments.remove(Attachments.items.length - 1);
        } else if (ctrl && event.key === Qt.Key_P) {
            Attachments.screen();
        } else if (event.key === Qt.Key_Up && !ctrl && input.text === "" && Agent.queue.count > 0) {
            input.text = Agent.popQueued();
            input.cursorPosition = input.text.length;
        } else if (ctrl && (event.key === Qt.Key_H || event.key === Qt.Key_O)) {
            root.page.togglePicker();
        } else if (ctrl && event.key === Qt.Key_S) {
            root.page.toggleSettings();
        } else if (root.page.picking && enter) {
            root.page.pickSession();
        } else if (root.page.picking && ctrl && vertical) {
            root.page.movePicker(down);
        } else if (root.page.picking && ctrl && event.key === Qt.Key_D) {
            root.page.askDelete();
        } else if (root.page.picking && ctrl && event.key === Qt.Key_R) {
            root.page.startRename("");
        } else if (ctrl && event.key === Qt.Key_M) {
            Agent.cycleModel();
        } else if (enter) {
            if (input.text.trim() === "" && Agent.activeId !== "") {
                Agent.enterKey();
            } else {
                root.page.submit(input.text);
                input.text = "";
            }
        } else if (ctrl && vertical && Agent.activeId !== "") {
            Agent.navKey(down);
        } else if (ctrl && event.key === Qt.Key_C && input.selectedText === "") {
            Agent.abort();
        } else if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && Agent.pendingApprovals > 0) {
            Agent.optionKey(event.key - Qt.Key_0);
        } else if (ctrl && (event.key === Qt.Key_Y || event.key === Qt.Key_N) && Agent.pendingApprovals > 0) {
            Agent.decideLatest(event.key === Qt.Key_Y ? "allow" : "deny");
        } else if (ctrl && event.key === Qt.Key_A && Agent.pendingApprovals > 0) {
            Agent.decideLatest("always");
        } else if (ctrl && event.key === Qt.Key_N) {
            root.page.newChat();
        } else if (ctrl && vertical) {
            root.page.scroll(down * root.page.lineStep);
        } else if (ctrl && (event.key === Qt.Key_D || event.key === Qt.Key_U)) {
            root.page.scroll((event.key === Qt.Key_D ? 1 : -1) * root.page.pageStep);
        } else {
            return false;
        }
        return true;
    }

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

            Keys.onEscapePressed: root.page.dismiss()
            Keys.onPressed: event => event.accepted = root.handleKey(event)

            Label {
                visible: input.text === ""
                text: root.page.renaming !== "" ? "Rename session…" : root.page.picking ? "Search sessions…" : Agent.busy ? "Queue a follow-up…" : `Ask ${Agent.label}…`
                color: Theme.alpha(Theme.muted, 0.7)
                font: input.font
            }
        }
    }
}
