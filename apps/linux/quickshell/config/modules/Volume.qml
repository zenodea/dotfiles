import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.style
import qs.widgets

BarButton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    function setVolume(v: real): void {
        if (!sink?.ready || !sink?.audio)
            return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1, v));
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    icon: muted || volume === 0 ? "󰝟" : volume < 0.34 ? "󰕿" : volume < 0.67 ? "󰖀" : "󰕾"
    iconColour: muted ? Theme.muted : Theme.fg
    labelWidth: 34
    label: `${Math.round(volume * 100)}%`
    labelColour: muted ? Theme.muted : Theme.fg

    level: muted ? 0 : volume
    title: muted ? "Muted" : `Volume ${Math.round(volume * 100)}%`
    detail: sink?.description ?? sink?.name ?? ""

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton)
            Quickshell.execDetached(["pavucontrol"]);
        else if (sink?.audio)
            sink.audio.muted = !sink.audio.muted;
    }
    onScrolled: delta => setVolume(volume + (delta > 0 ? 0.02 : -0.02))
}
