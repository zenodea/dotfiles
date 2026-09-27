import QtQuick
import qs.services
import qs.style
import qs.widgets

// mode chips on the left, search field on the right
Item {
    id: root

    property var modes: []
    property string mode: ""
    readonly property alias input: input

    signal step(string direction)
    signal page(int direction)
    signal accepted
    signal nextMode

    height: Metrics.launcherHeader

    Row {
        id: chips

        height: parent.height

        Repeater {
            model: root.modes

            Rectangle {
                id: chip

                required property var modelData

                readonly property bool active: root.mode === modelData.id

                width: 118
                height: chips.height
                color: chipArea.containsMouse && !active ? Theme.alpha(Theme.fg, 0.07) : "transparent"

                Label {
                    anchors.centerIn: parent
                    text: chip.modelData.label
                    color: chip.active ? Theme.accent : Theme.muted
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Metrics.borderWidth * 2
                    color: Theme.accent
                    visible: chip.active
                }

                MouseArea {
                    id: chipArea

                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        Panels.launcher = chip.modelData.id;
                        input.forceActiveFocus();
                    }
                }
            }
        }
    }

    Rectangle {
        x: chips.width
        width: Metrics.borderWidth
        height: parent.height
        color: Theme.alpha(Theme.fg, 0.15)
    }

    TextInput {
        id: input

        x: chips.width + Metrics.drawerPadding
        width: parent.width - x - Metrics.drawerPadding
        height: parent.height
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.fgBright
        font.family: Theme.fontMono
        font.pixelSize: 14
        selectionColor: Theme.alpha(Theme.accent, 0.35)
        selectedTextColor: Theme.fgBright
        clip: true

        Keys.onEscapePressed: Panels.close()
        Keys.onDownPressed: root.step("down")
        Keys.onUpPressed: root.step("up")
        Keys.onPressed: event => {
            if (!(event.modifiers & Qt.ControlModifier))
                return;
            const steps = {
                [Qt.Key_J]: "down",
                [Qt.Key_K]: "up",
                [Qt.Key_L]: "right",
                [Qt.Key_H]: "left"
            };
            if (steps[event.key])
                root.step(steps[event.key]);
            else if (event.key === Qt.Key_D || event.key === Qt.Key_U)
                root.page(event.key === Qt.Key_D ? 1 : -1);
            else
                return;
            event.accepted = true;
        }
        Keys.onReturnPressed: root.accepted()
        Keys.onEnterPressed: root.accepted()
        Keys.onTabPressed: root.nextMode()

        Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: `Search ${root.mode}…`
            color: Theme.alpha(Theme.muted, 0.7)
            font: input.font
        }
    }
}
