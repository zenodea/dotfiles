import QtQuick
import Quickshell.Services.Pipewire
import qs.style
import qs.widgets

BarButton {
    id: root

    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property bool muted: source?.audio?.muted ?? false

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSource]
    }

    shown: muted
    icon: "󰍭"
    iconColour: Theme.red

    title: "Microphone muted"
    detail: source?.description ?? source?.name ?? ""

    onClicked: {
        if (source?.audio)
            source.audio.muted = false;
    }
}
