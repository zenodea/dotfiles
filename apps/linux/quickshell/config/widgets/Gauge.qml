import QtQuick
import qs.style

Item {
    id: root

    property real value: 0
    property string label: ""
    property string caption: ""
    property color fill: Theme.accent

    readonly property color track: Theme.alpha(Theme.fg, 0.14)

    property real shown: 0

    implicitWidth: 74
    implicitHeight: 74

    onValueChanged: shown = Math.max(0, Math.min(1, value))
    onFillChanged: canvas.requestPaint()
    onTrackChanged: canvas.requestPaint()
    onShownChanged: canvas.requestPaint()

    Behavior on shown {
        Ease {}
    }

    Canvas {
        id: canvas

        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();

            const cx = width / 2;
            const cy = height / 2;
            const radius = Math.min(width, height) / 2 - 5;
            const start = Math.PI * 0.75;
            const sweep = Math.PI * 1.5;

            ctx.lineWidth = 5;
            ctx.lineCap = "butt";

            ctx.strokeStyle = root.track;
            ctx.beginPath();
            ctx.arc(cx, cy, radius, start, start + sweep);
            ctx.stroke();

            if (root.shown > 0) {
                ctx.strokeStyle = root.fill;
                ctx.beginPath();
                ctx.arc(cx, cy, radius, start, start + sweep * root.shown);
                ctx.stroke();
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: -1

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: Theme.fgBright
            font.pixelSize: 13
            font.bold: true
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.caption !== ""
            text: root.caption
            color: Theme.muted
            font.pixelSize: 8
        }
    }
}
