import QtQuick
import Quickshell.Services.UPower
import qs.services
import qs.style
import qs.widgets

Label {
    height: Metrics.launcherFooter
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    text: {
        const parts = [`up ${SysInfo.uptimeText}`];
        if (Updates.summary)
            parts.push(Updates.summary);
        if (UPower.displayDevice?.isLaptopBattery ?? false)
            parts.push(`battery ${Math.round((UPower.displayDevice.percentage <= 1 ? UPower.displayDevice.percentage * 100 : UPower.displayDevice.percentage))}%`);
        if (Notifs.count > 0)
            parts.push(`${Notifs.count} notification${Notifs.count === 1 ? "" : "s"} waiting`);
        return parts.join("  ·  ");
    }
    color: Theme.muted
    font.pixelSize: 10
}
