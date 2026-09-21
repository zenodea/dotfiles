import QtQuick
import qs.services
import qs.widgets

Grid {
    id: capture

    columns: 2
    spacing: 6

    readonly property real cell: (width - spacing) / 2

    PillButton {
        width: capture.cell
        maxTextWidth: capture.cell - 42
        icon: "󰹑"
        label: "Region"
        enabled: Tools.has("grim") && Tools.has("slurp")
        onClicked: Screenshot.take("region")
    }

    PillButton {
        width: capture.cell
        maxTextWidth: capture.cell - 42
        icon: "󰆏"
        label: "Copy region"
        enabled: Tools.has("grim") && Tools.has("slurp") && Tools.has("wl-copy")
        onClicked: Screenshot.take("clip")
    }

    PillButton {
        width: capture.cell
        maxTextWidth: capture.cell - 42
        icon: "󰍹"
        label: "Screen"
        enabled: Tools.has("grim")
        onClicked: Screenshot.take("screen")
    }

    PillButton {
        width: capture.cell
        maxTextWidth: capture.cell - 42
        icon: "󰆏"
        label: "Copy screen"
        enabled: Tools.has("grim") && Tools.has("wl-copy")
        onClicked: Screenshot.take("clipScreen")
    }

    PillButton {
        width: capture.cell
        maxTextWidth: capture.cell - 42
        icon: Recorder.recording ? "󰙧" : "󰑊"
        label: Recorder.recording ? "Stop" : "Record screen"
        active: Recorder.recording
        enabled: Tools.has("wf-recorder")
        onClicked: Recorder.toggle(false)
    }

    PillButton {
        width: capture.cell
        maxTextWidth: capture.cell - 42
        icon: "󰻂"
        label: "Record region"
        enabled: Tools.has("wf-recorder") && Tools.has("slurp") && !Recorder.recording
        onClicked: Recorder.toggle(true)
    }
}
