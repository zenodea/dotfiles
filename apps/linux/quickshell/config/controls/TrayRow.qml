pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.services

Row {
    spacing: 8

    Repeater {
        model: Tray.items

        Item {
            id: entry

            required property SystemTrayItem modelData

            width: 22
            height: 22

            Image {
                anchors.fill: parent
                source: entry.modelData.icon
                sourceSize.width: 44
                sourceSize.height: 44
            }

            TrayMenu {
                id: menu

                trayItem: entry.modelData
                anchorWindow: entry.QsWindow.window
                anchorX: 0
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton && entry.modelData.hasMenu) {
                        menu.anchorX = entry.mapToItem(null, entry.width / 2, 0).x;
                        menu.open();
                        return;
                    }
                    if (mouse.button === Qt.RightButton) {
                        entry.modelData.secondaryActivate();
                        return;
                    }
                    entry.modelData.activate();
                    Panels.close();
                }
            }
        }
    }
}
