import QtQuick
import qs.style

Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property bool active: false
    property bool enabled: true
    property real maxTextWidth: 0

    signal clicked

    implicitWidth: row.implicitWidth + Metrics.itemPadding * 2
    implicitHeight: 30

    color: active && enabled ? Theme.alpha(Theme.accent, 0.18) : area.containsMouse && enabled ? Theme.alpha(Theme.fg, 0.09) : Theme.alpha(Theme.fg, 0.05)

    Behavior on color {
        ColorAnimation {
            duration: Metrics.shortAnim
        }
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: Metrics.gap

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon !== ""
            text: root.icon
            color: !root.enabled ? Theme.alpha(Theme.muted, 0.4) : root.active ? Theme.accent : Theme.fg
        }

        Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.label !== ""
            width: root.maxTextWidth > 0 ? Math.min(implicitWidth, root.maxTextWidth) : implicitWidth
            elide: Text.ElideRight
            text: root.label
            color: !root.enabled ? Theme.alpha(Theme.muted, 0.4) : root.active ? Theme.accent : Theme.fg
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        onClicked: root.clicked()
    }
}
