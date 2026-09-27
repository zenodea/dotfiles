import QtQuick
import qs.style

Item {
    id: root

    property string label: ""
    property string value: ""
    property color valueColour: Theme.fg

    implicitWidth: Math.max(Metrics.popoutMinWidth - Metrics.popoutPadding * 2, labelText.implicitWidth + valueText.implicitWidth + Metrics.sectionSpacing)
    implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)

    Label {
        id: labelText

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: Theme.muted
    }

    Label {
        id: valueText

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.value
        color: root.valueColour
    }
}
