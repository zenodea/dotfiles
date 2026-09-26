pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

Singleton {
    id: root

    readonly property var hidden: ["Mullvad VPN_status_icon_1"]

    readonly property var items: SystemTray.items.values.filter(i => !root.hidden.includes(i.id))
}
