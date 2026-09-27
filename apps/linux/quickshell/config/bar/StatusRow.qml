import QtQuick
import Quickshell
import qs.style

Row {
    id: root

    required property ShellScreen screen

    height: Metrics.barHeight

    AgentStatus {
        screen: root.screen
    }

    CapsLock {
        screen: root.screen
    }

    Mic {
        screen: root.screen
    }

    Volume {
        screen: root.screen
    }

    Backlight {
        screen: root.screen
    }

    Performance {
        screen: root.screen
    }

    VpnStatus {
        screen: root.screen
    }

    NetworkStatus {
        screen: root.screen
    }

    BluetoothStatus {
        screen: root.screen
    }

    NetGraph {
        screen: root.screen
    }

    Battery {
        screen: root.screen
    }
}
