pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.services

Singleton {
    id: root

    property string kind: ""
    property real level: 0
    property bool muted: false
    property bool ready: false
    property bool active: false

    readonly property bool shown: active && !Panels.drawer

    readonly property string icon: {
        if (kind === "brightness")
            return level < 0.34 ? "󰃞" : level < 0.67 ? "󰃟" : "󰃠";
        if (muted || level === 0)
            return "󰝟";
        return level < 0.34 ? "󰕿" : level < 0.67 ? "󰖀" : "󰕾";
    }

    function trigger(kind: string, level: real, muted: bool): void {
        if (!ready)
            return;
        root.kind = kind;
        root.level = level;
        root.muted = muted;
        root.active = true;
        hide.restart();
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    Connections {
        function onVolumeChanged(): void {
            root.trigger("volume", target.volume, target.muted);
        }

        function onMutedChanged(): void {
            root.trigger("volume", target.volume, target.muted);
        }

        target: Pipewire.defaultAudioSink?.audio ?? null
    }

    Connections {
        function onPercentChanged(): void {
            root.trigger("brightness", Brightness.percent / 100, false);
        }

        target: Brightness
    }

    Timer {
        running: true
        interval: 2000
        onTriggered: root.ready = true
    }

    Timer {
        id: hide

        interval: 1600
        onTriggered: root.active = false
    }
}
