import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.services
import qs.style
import qs.widgets

BarButton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property real raw: device?.percentage ?? 0
    readonly property int percent: Math.round(raw <= 1 ? raw * 100 : raw)
    readonly property bool charging: device?.state === UPowerDeviceState.Charging || device?.state === UPowerDeviceState.FullyCharged

    readonly property var ramp: ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]

    function duration(seconds: real): string {
        if (!seconds || seconds <= 0)
            return "";
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        return h > 0 ? `${h}h ${m}m` : `${m}m`;
    }

    shown: device?.isLaptopBattery ?? false

    icon: charging ? "󰂄" : ramp[Math.min(9, Math.floor(percent / 10))]
    iconColour: charging ? Theme.green : percent <= 10 ? Theme.red : percent <= 20 ? Theme.yellow : Theme.fg
    label: `${percent}%`

    readonly property string remaining: {
        if (charging) {
            const left = duration(device?.timeToFull ?? 0);
            return left ? `${left} until full` : "Charging";
        }
        const left = duration(device?.timeToEmpty ?? 0);
        return left ? `${left} remaining` : "On battery";
    }

    title: `Battery ${percent}%`

    popoutContent: Component {
        Column {
            spacing: 3

            PopoutTitle {
                text: root.title
            }

            PopoutLabel {
                text: root.remaining
            }

            Item {
                width: 1
                height: 4
            }

            PopoutLevel {
                width: limits.width
                level: root.percent / 100
            }

            Item {
                width: 1
                height: 2
            }

            PopoutRow {
                visible: Math.abs(root.device?.changeRate ?? 0) > 0
                label: root.charging ? "Charging at" : "Draining at"
                value: `${Math.abs(root.device?.changeRate ?? 0).toFixed(1)} W`
            }

            PopoutRow {
                visible: (root.device?.healthSupported ?? false)
                label: "Health"
                value: `${Math.round(root.device?.healthPercentage ?? 0)}%`
            }

            Item {
                width: 1
                height: 8
            }

            Rectangle {
                width: limits.width
                height: Metrics.borderWidth
                color: Theme.alpha(Theme.fg, 0.15)
            }

            Item {
                width: 1
                height: 8
            }

            Text {
                text: Charge.capped ? `CHARGE LIMIT · ${Charge.limit}%` : "CHARGE LIMIT"
                color: Theme.muted
                font.family: Theme.fontMono
                font.pixelSize: 10
                font.letterSpacing: 1
                renderType: Text.NativeRendering
            }

            Item {
                width: 1
                height: 4
            }

            Row {
                id: limits

                width: 232
                spacing: 1

                readonly property real cell: (width - (Charge.presets.length - 1)) / Charge.presets.length

                Repeater {
                    model: Charge.presets

                    PillButton {
                        required property int modelData

                        width: limits.cell
                        label: modelData >= 100 ? "Full" : `${modelData}%`
                        active: Charge.limit === modelData
                        enabled: Charge.usable
                        onClicked: Charge.set(modelData)
                    }
                }
            }
        }
    }
}
