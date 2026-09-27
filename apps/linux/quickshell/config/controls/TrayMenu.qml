pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.style
import qs.widgets

PopupWindow {
    id: root

    required property var trayItem
    required property var anchorWindow
    required property real anchorX

    property var trail: []

    readonly property var currentHandle: trail.length > 0 ? trail[trail.length - 1] : trayItem?.menu ?? null

    function open(): void {
        trail = [];
        visible = true;
    }

    function close(): void {
        visible = false;
        trail = [];
    }

    anchor {
        window: root.anchorWindow
        rect.x: Math.max(Metrics.strip, root.anchorX - root.implicitWidth / 2)
        rect.y: Metrics.barHeight
    }

    implicitWidth: Math.max(160, column.implicitWidth + Metrics.popoutPadding * 2)
    implicitHeight: column.implicitHeight + Metrics.popoutPadding
    color: "transparent"
    visible: false

    QsMenuOpener {
        id: opener

        menu: root.currentHandle
    }

    Item {
        anchors.fill: parent

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            blurMax: Metrics.shadowBlur
            shadowColor: Qt.rgba(0, 0, 0, Metrics.shadowOpacity)
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.bg

            Column {
                id: column

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: Metrics.popoutPadding / 2

                Rectangle {
                    width: parent.width
                    height: root.trail.length > 0 ? 24 : 0
                    visible: height > 0
                    color: backArea.containsMouse ? Theme.alpha(Theme.fg, 0.08) : "transparent"

                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: Metrics.popoutPadding
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰅁  back"
                        color: Theme.muted
                    }

                    MouseArea {
                        id: backArea

                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.trail = root.trail.slice(0, -1)
                    }
                }

                Repeater {
                    model: opener.children

                    Item {
                        id: entry

                        required property QsMenuEntry modelData

                        width: column.width
                        height: modelData.isSeparator ? 7 : 24

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: Metrics.popoutPadding
                            anchors.rightMargin: Metrics.popoutPadding
                            visible: entry.modelData.isSeparator
                            height: Metrics.borderWidth
                            color: Theme.alpha(Theme.fg, 0.15)
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: !entry.modelData.isSeparator
                            color: itemArea.containsMouse && entry.modelData.enabled ? Theme.alpha(Theme.fg, 0.08) : "transparent"

                            Label {
                                anchors.left: parent.left
                                anchors.leftMargin: Metrics.popoutPadding
                                anchors.verticalCenter: parent.verticalCenter
                                text: (entry.modelData.checkState === Qt.Checked ? "󰄲  " : "") + entry.modelData.text
                                color: !entry.modelData.enabled ? Theme.alpha(Theme.muted, 0.5) : itemArea.containsMouse ? Theme.accent : Theme.fg
                            }

                            Icon {
                                anchors.right: parent.right
                                anchors.rightMargin: Metrics.popoutPadding
                                anchors.verticalCenter: parent.verticalCenter
                                visible: entry.modelData.hasChildren
                                text: "󰅂"
                                color: Theme.muted
                                font.pixelSize: 11
                            }

                            MouseArea {
                                id: itemArea

                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: entry.modelData.enabled && !entry.modelData.isSeparator
                                onClicked: {
                                    if (entry.modelData.hasChildren) {
                                        root.trail = [...root.trail, entry.modelData];
                                        return;
                                    }
                                    entry.modelData.triggered();
                                    root.close();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
