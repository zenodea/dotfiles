pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.popouts
import qs.services
import qs.style

Row {
    id: root

    property ShellScreen screen: null
    property var window: null

    spacing: 0
    leftPadding: SystemTray.items.values.length > 0 ? Metrics.sectionSpacing / 2 : 0
    rightPadding: leftPadding

    Repeater {
        model: SystemTray.items

        Rectangle {
            id: entry

            required property SystemTrayItem modelData

            width: Metrics.iconSize + Metrics.itemPadding
            height: Metrics.barHeight
            radius: Metrics.radius
            color: "transparent"

            Image {
                anchors.centerIn: parent
                source: entry.modelData.icon
                sourceSize.width: Metrics.iconSize
                sourceSize.height: Metrics.iconSize
                width: Metrics.iconSize
                height: Metrics.iconSize
                smooth: true
            }

            TrayMenu {
                id: menu

                trayItem: entry.modelData
                anchorWindow: root.window
                anchorX: 0
            }

            MouseArea {
                id: area

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onEntered: Popouts.show(entry, root.screen, {
                        title: entry.modelData.title || entry.modelData.id,
                        detail: entry.modelData.tooltipTitle || ""
                    })
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton || entry.modelData.onlyMenu) {
                        if (entry.modelData.hasMenu) {
                            menu.anchorX = entry.mapToItem(null, entry.width / 2, 0).x;
                            menu.open();
                        } else {
                            entry.modelData.secondaryActivate();
                        }
                        return;
                    }
                    entry.modelData.activate();
                }
            }
        }
    }
}
