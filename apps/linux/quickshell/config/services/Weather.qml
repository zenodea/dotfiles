pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string place: "London"

    property bool known: false
    property real latitude: 0
    property real longitude: 0
    property real temp: 0
    property real high: 0
    property real low: 0
    property int code: 0
    property bool day: true

    readonly property var kinds: [
        {
            upTo: 0,
            icon: "󰖙",
            night: "󰖔",
            label: "Clear"
        },
        {
            upTo: 2,
            icon: "󰖕",
            night: "󰼱",
            label: "Partly cloudy"
        },
        {
            upTo: 3,
            icon: "󰖐",
            label: "Overcast"
        },
        {
            upTo: 48,
            icon: "󰖑",
            label: "Fog"
        },
        {
            upTo: 57,
            icon: "󰖗",
            label: "Drizzle"
        },
        {
            upTo: 67,
            icon: "󰖖",
            label: "Rain"
        },
        {
            upTo: 77,
            icon: "󰖘",
            label: "Snow"
        },
        {
            upTo: 82,
            icon: "󰖗",
            label: "Showers"
        },
        {
            upTo: 86,
            icon: "󰖘",
            label: "Snow showers"
        },
        {
            upTo: 99,
            icon: "󰖓",
            label: "Thunderstorm"
        }
    ]

    readonly property var kind: kinds.find(k => code <= k.upTo) ?? kinds[2]
    readonly property string icon: day ? kind.icon : kind.night ?? kind.icon
    readonly property string label: kind.label

    function refresh(): void {
        if (latitude === 0 && longitude === 0)
            locate.running = true;
        else
            forecast.running = true;
    }

    function parse(text: string): var {
        try {
            return JSON.parse(text);
        } catch (e) {
            return null;
        }
    }

    Process {
        id: locate

        running: true
        command: ["curl", "-fsSG", "--max-time", "10", "--data-urlencode", `name=${root.place}`, "https://geocoding-api.open-meteo.com/v1/search?count=1"]

        stdout: StdioCollector {
            onStreamFinished: {
                const found = root.parse(text)?.results?.[0];
                if (!found)
                    return;
                root.latitude = found.latitude;
                root.longitude = found.longitude;
                forecast.running = true;
            }
        }
    }

    Process {
        id: forecast

        command: ["curl", "-fsS", "--max-time", "10", `https://api.open-meteo.com/v1/forecast?latitude=${root.latitude}&longitude=${root.longitude}&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1`]

        stdout: StdioCollector {
            onStreamFinished: {
                const d = root.parse(text);
                if (!d?.current)
                    return;
                root.temp = d.current.temperature_2m;
                root.code = d.current.weather_code;
                root.day = d.current.is_day === 1;
                root.high = d.daily.temperature_2m_max[0];
                root.low = d.daily.temperature_2m_min[0];
                root.known = true;
            }
        }
    }

    Timer {
        running: true
        repeat: true
        interval: root.known ? 1800000 : 60000
        onTriggered: root.refresh()
    }
}
