pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.UPower
import qs.style

Row {
    id: profiles

    spacing: 1

    readonly property var options: [
        {
            id: PowerProfile.PowerSaver,
            icon: "󰾆",
            label: "Saver"
        },
        {
            id: PowerProfile.Balanced,
            icon: "󰾅",
            label: "Balanced"
        },
        {
            id: PowerProfile.Performance,
            icon: "󰓅",
            label: "Performance"
        }
    ]

    readonly property int shown: PowerProfiles.hasPerformanceProfile ? 3 : 2

    Repeater {
        model: profiles.options

        Rectangle {
            id: segment

            required property var modelData

            readonly property bool active: PowerProfiles.profile === modelData.id

            visible: modelData.id !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile
            width: (profiles.width - (profiles.shown - 1)) / profiles.shown
            height: 30
            color: active ? Theme.alpha(Theme.accent, 0.22) : segmentArea.containsMouse ? Theme.alpha(Theme.fg, 0.09) : Theme.alpha(Theme.fg, 0.05)

            Behavior on color {
                ColorAnimation {
                    duration: Metrics.shortAnim
                }
            }

            Row {
                anchors.centerIn: parent
                spacing: Metrics.gap

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: segment.modelData.icon
                    color: segment.active ? Theme.accent : Theme.muted
                    font.family: Metrics.iconFont
                    font.pixelSize: 13
                    renderType: Text.NativeRendering
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: segment.modelData.label
                    color: segment.active ? Theme.accent : Theme.fg
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                    renderType: Text.NativeRendering
                }
            }

            MouseArea {
                id: segmentArea

                anchors.fill: parent
                hoverEnabled: true
                onClicked: PowerProfiles.profile = segment.modelData.id
            }
        }
    }
}
