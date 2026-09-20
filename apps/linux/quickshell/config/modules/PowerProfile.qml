import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.style
import qs.widgets

BarButton {
    id: root

    readonly property int profile: PowerProfiles.profile

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
    detail: "Power profile"

    onClicked: {
        if (profile === PowerProfile.PowerSaver)
            PowerProfiles.profile = PowerProfile.Balanced;
        else if (profile === PowerProfile.Balanced && PowerProfiles.hasPerformanceProfile)
            PowerProfiles.profile = PowerProfile.Performance;
        else
            PowerProfiles.profile = PowerProfile.PowerSaver;
    }
}
