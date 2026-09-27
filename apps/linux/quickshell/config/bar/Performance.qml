import QtQuick
import Quickshell.Services.UPower
import qs.style
import qs.widgets

BarButton {
    id: root

    readonly property int profile: PowerProfiles.profile

    readonly property var options: [
        {
            id: PowerProfile.PowerSaver,
            icon: "󰾆",
            label: "Power saver"
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

    function name(p: int): string {
        if (p === PowerProfile.Performance)
            return "Performance";
        if (p === PowerProfile.PowerSaver)
            return "Power saver";
        return "Balanced";
    }

    icon: profile === PowerProfile.Performance ? "󰓅" : profile === PowerProfile.PowerSaver ? "󰾆" : "󰾅"
    iconColour: profile === PowerProfile.Performance ? Theme.orange : profile === PowerProfile.PowerSaver ? Theme.green : Theme.fg

    title: name(profile)

    popoutContent: Component {
        Column {
            spacing: 4

            PopoutTitle {
                text: "Power profile"
            }

            Repeater {
                model: root.options

                PillButton {
                    id: option

                    required property var modelData

                    width: 150
                    icon: modelData.icon
                    label: modelData.label
                    active: root.profile === modelData.id
                    visible: modelData.id !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile
                    onClicked: PowerProfiles.profile = option.modelData.id
                }
            }

            PopoutLabel {
                text: PowerProfiles.degradationReason !== PerformanceDegradationReason.None ? "Performance limited" : ""
            }
        }
    }

    onClicked: {
        if (profile === PowerProfile.PowerSaver)
            PowerProfiles.profile = PowerProfile.Balanced;
        else if (profile === PowerProfile.Balanced && PowerProfiles.hasPerformanceProfile)
            PowerProfiles.profile = PowerProfile.Performance;
        else
            PowerProfiles.profile = PowerProfile.PowerSaver;
    }
}
