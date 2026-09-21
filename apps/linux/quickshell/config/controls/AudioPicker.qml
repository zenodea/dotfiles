pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.style
import qs.widgets

Column {
    id: root

    readonly property var nodes: Pipewire.nodes.values.filter(n => n.audio)
    readonly property var outputs: nodes.filter(n => n.isSink && !n.isStream)
    readonly property var inputs: nodes.filter(n => !n.isSink && !n.isStream)
    readonly property var hidden: ["speech-dispatcher-dummy"]
    readonly property var streams: nodes.filter(n => n.isSink && n.isStream && !hidden.includes(n.name))

    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property bool micMuted: source?.audio?.muted ?? false

    spacing: 2

    PwObjectTracker {
        objects: root.nodes
    }

    PopoutLabel {
        visible: root.outputs.length > 1
        text: "Output"
    }

    Repeater {
        model: ScriptModel {
            values: root.outputs.length > 1 ? root.outputs : []
        }

        PickRow {
            required property PwNode modelData

            width: root.width
            icon: "󰓃"
            label: modelData.description || modelData.name
            active: modelData === Pipewire.defaultAudioSink
            onClicked: Pipewire.preferredDefaultAudioSink = modelData
        }
    }

    Toggle {
        width: parent.width
        visible: !!root.source
        icon: root.micMuted ? "󰍭" : "󰍬"
        label: "Microphone"
        checked: !root.micMuted
        onToggled: {
            if (root.source?.audio)
                root.source.audio.muted = !root.source.audio.muted;
        }
    }

    Repeater {
        model: ScriptModel {
            values: root.inputs.length > 1 ? root.inputs : []
        }

        PickRow {
            required property PwNode modelData

            width: root.width
            icon: "󰍬"
            label: modelData.description || modelData.name
            active: modelData === Pipewire.defaultAudioSource
            onClicked: Pipewire.preferredDefaultAudioSource = modelData
        }
    }

    Repeater {
        model: ScriptModel {
            values: root.streams
        }

        Column {
            id: stream

            required property PwNode modelData

            width: root.width
            topPadding: 6
            spacing: 2

            PopoutLabel {
                width: parent.width
                elide: Text.ElideRight
                text: stream.modelData.properties["application.name"] || stream.modelData.description || stream.modelData.name
            }

            SliderRow {
                width: parent.width
                icon: stream.modelData.audio.muted ? "󰝟" : "󰕾"
                iconColour: stream.modelData.audio.muted ? Theme.muted : Theme.fg
                valueText: `${Math.round(stream.modelData.audio.volume * 100)}%`
                value: stream.modelData.audio.muted ? 0 : stream.modelData.audio.volume
                onIconClicked: stream.modelData.audio.muted = !stream.modelData.audio.muted
                onMoved: v => {
                    stream.modelData.audio.muted = false;
                    stream.modelData.audio.volume = v;
                }
            }
        }
    }
}
