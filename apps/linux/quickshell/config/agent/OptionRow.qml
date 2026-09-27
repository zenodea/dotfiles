import QtQuick
import qs.style
import qs.widgets

Rectangle {
    id: root

    property int number: 0
    property string label: ""
    property string description: ""
    property bool picked: false
    property bool cursor: false

    signal clicked

    implicitHeight: body.implicitHeight + 10
    color: picked ? Theme.alpha(Theme.accent, 0.18) : cursor || area.containsMouse ? Theme.alpha(Theme.fg, 0.09) : Theme.alpha(Theme.fg, 0.03)

    Behavior on color {
        ColorAnimation {
            duration: Metrics.shortAnim
        }
    }

    AccentBar {
        visible: root.cursor
    }

    Label {
        x: 6
        y: 5
        text: root.number
        color: root.picked ? Theme.accent : Theme.muted
        font.pixelSize: 13
    }

    Column {
        id: body

        x: 22
        y: 5
        width: parent.width - 28

        Label {
            width: parent.width
            wrapMode: Text.Wrap
            text: root.label
            color: root.picked ? Theme.accent : Theme.fg
            font.pixelSize: 13
        }

        Label {
            visible: text !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: root.description
            color: Theme.muted
            font.pixelSize: 12
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
