import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.providers
import qs.services

Scope {
    id: root

    readonly property bool open: Panels.palette

    onOpenChanged: {
        if (!open)
            return;
        ScriptProvider.refresh();
        RunProvider.dismiss();
        search.scope = null;
        view.reset();
        view.input.forceActiveFocus();
        focusAgain.tries = 0;
        focusAgain.restart();
    }

    GlobalShortcut {
        name: "palette"
        description: "Toggle the command palette"
        onPressed: Panels.togglePalette()
    }

    PaletteModel {
        id: search
    }

    Timer {
        id: focusAgain

        property int tries: 0

        interval: 16
        repeat: true
        onTriggered: {
            if (!root.open || view.input.activeFocus || tries >= 30) {
                stop();
                return;
            }
            tries++;
            view.input.forceActiveFocus();
        }
    }

    PanelWindow {
        id: box

        screen: Panels.screen ?? Quickshell.screens[0]
        color: "transparent"
        implicitWidth: view.width
        implicitHeight: view.height
        WlrLayershell.namespace: "dotfiles-palette"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        anchors.top: true
        margins.top: Math.round((screen?.height ?? 1080) * 0.16)

        mask: Region {
            item: root.open ? view : null
        }

        PaletteView {
            id: view

            visible: root.open
            model: search
            onDismissed: Panels.palette = false
            onActivated: (entry, action) => {
                if (!action.stay)
                    Panels.palette = false;
                search.run(entry, action);
            }
        }
    }

    PanelWindow {
        id: outside

        screen: box.screen
        visible: root.open
        color: "transparent"
        WlrLayershell.namespace: "dotfiles-palette-outside"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        mask: Region {
            item: everywhere

            Region {
                x: Math.round((outside.width - view.width) / 2)
                y: box.margins.top
                width: view.width
                height: view.height
                intersection: Intersection.Subtract
            }
        }

        MouseArea {
            id: everywhere

            anchors.fill: parent
            onClicked: Panels.palette = false
        }
    }
}
