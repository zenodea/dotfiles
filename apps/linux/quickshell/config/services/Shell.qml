pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

Singleton {
    id: root

    readonly property var hiddenTray: ["Mullvad VPN_status_icon_1"]

    readonly property var trayItems: SystemTray.items.values.filter(i => !root.hiddenTray.includes(i.id))
}
