import QtQuick
import qs.style

Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property bool active: false
    property bool enabled: true

    signal clicked

    implicitWidth: row.implicitWidth + Metrics.itemPadding * 2
    implicitHeight: 30

    color: active ? Theme.alpha(Theme.accent, 0.18) : area.containsMouse && enabled ? Theme.alpha(Theme.fg, 0.09) : Theme.alpha(Theme.fg, 0.05)

    Behavior on color {
        ColorAnimation {
            duration: Metrics.shortAnim
        }
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: Metrics.gap

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon !== ""
            text: root.icon
            color: !root.enabled ? Theme.alpha(Theme.muted, 0.4) : root.active ? Theme.accent : Theme.fg
            font.family: Metrics.iconFont
            font.pixelSize: 14
            renderType: Text.NativeRendering
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.label !== ""
            text: root.label
            color: !root.enabled ? Theme.alpha(Theme.muted, 0.4) : root.active ? Theme.accent : Theme.fg
            font.family: Theme.fontMono
            font.pixelSize: 11
            renderType: Text.NativeRendering
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
