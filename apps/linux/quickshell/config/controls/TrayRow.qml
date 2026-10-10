pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.services
import qs.style

Row {
    spacing: 8

    Repeater {
        model: Tray.items

        Item {
            id: entry

            required property SystemTrayItem modelData

            readonly property bool focused: Nav.current === entry

            width: 22
            height: 22

            function activate(): void {
                entry.modelData.activate();
                Panels.close();
            }

            function menu(): void {
                if (!entry.modelData.hasMenu) {
                    entry.modelData.secondaryActivate();
                    return;
                }
                trayMenu.anchorX = entry.mapToItem(null, entry.width / 2, 0).x;
                trayMenu.open();
            }

            Component.onCompleted: Nav.register(entry)
            Component.onDestruction: Nav.unregister(entry)

            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                color: "transparent"
                border.width: entry.focused ? Metrics.borderWidth : 0
                border.color: Theme.accent
            }

            Image {
                anchors.fill: parent
                source: entry.modelData.icon
                sourceSize.width: 44
                sourceSize.height: 44
            }

            TrayMenu {
                id: trayMenu

                trayItem: entry.modelData
                anchorWindow: entry.QsWindow.window
                anchorX: 0
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton)
                        entry.menu();
                    else
                        entry.activate();
                }
            }
        }
    }
}
