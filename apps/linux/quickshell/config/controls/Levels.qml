import QtQuick
import Quickshell.Services.Pipewire
import qs.services
import qs.style
import qs.widgets

Column {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    spacing: 10

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    SliderRow {
        width: parent.width
        icon: root.muted || root.volume === 0 ? "󰝟" : root.volume < 0.34 ? "󰕿" : root.volume < 0.67 ? "󰖀" : "󰕾"
        iconColour: root.muted ? Theme.muted : Theme.fg
        valueText: `${Math.round(root.volume * 100)}%`
        value: root.muted ? 0 : root.volume
        onIconClicked: {
            if (root.sink?.audio)
                root.sink.audio.muted = !root.sink.audio.muted;
        }
        onMoved: v => {
            if (!root.sink?.audio)
                return;
            root.sink.audio.muted = false;
            root.sink.audio.volume = v;
        }
    }

    SliderRow {
        width: parent.width
        visible: Brightness.available
        icon: Brightness.percent < 34 ? "󰃞" : Brightness.percent < 67 ? "󰃟" : "󰃠"
        valueText: Brightness.writable ? `${Brightness.percent}%` : "×"
        value: Brightness.percent / 100
        fill: Theme.yellow
        adjustable: Brightness.writable
        onMoved: v => Brightness.set(Math.round(v * 100))
    }
}
