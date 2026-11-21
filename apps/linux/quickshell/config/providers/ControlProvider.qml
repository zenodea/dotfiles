pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import qs.services

Singleton {
    id: root

    readonly property string id: "controls"
    readonly property string label: "Controls"
    readonly property string tag: "Control"
    readonly property string glyph: "\u{f04c5}"

    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property var outputs: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)

    readonly property var entries: {
        const found = [];
        if (wifi) {
            const joined = wifi.networks?.values.find(n => n.connected)?.name ?? "";
            found.push({
                name: "Wi-Fi",
                sub: !Networking.wifiEnabled ? "Radio is off" : joined || "Not connected",
                keywords: "wifi wireless network internet toggle",
                icon: Networking.wifiEnabled ? "\u{f05a9}" : "\u{f05aa}",
                on: Networking.wifiEnabled,
                run: () => Networking.wifiEnabled = !Networking.wifiEnabled
            });
        }
        if (adapter) {
            const devices = Bluetooth.devices.values.filter(d => d.paired || d.connected).sort((a, b) => b.connected - a.connected);
            const linked = devices.filter(d => d.connected).map(d => d.name);
            found.push({
                name: "Bluetooth",
                sub: !adapter.enabled ? "Radio is off" : linked.join(", ") || "No device connected",
                keywords: "bt wireless headphones devices toggle",
                icon: adapter.enabled ? "\u{f00af}" : "\u{f00b2}",
                on: adapter.enabled,
                more: "Show devices",
                run: () => root.adapter.enabled = !root.adapter.enabled,
                children: !adapter.enabled ? [] : devices.map(d => ({
                            name: `bluetooth:${d.name}`,
                            title: d.name,
                            sub: d.batteryAvailable ? `Battery ${Math.round(d.battery * 100)}%` : "",
                            icon: d.connected ? "\u{f00b1}" : "\u{f00af}",
                            state: d.connected ? "Connected" : "Paired",
                            on: d.connected ? true : undefined,
                            verb: d.connected ? "Disconnect" : "Connect",
                            run: () => d.connected ? d.disconnect() : d.connect()
                        }))
            });
        }
        if (Vpn.available)
            found.push({
                name: "VPN",
                sub: Vpn.connected ? Vpn.location || "Connected" : "Disconnected",
                keywords: "mullvad privacy tunnel toggle",
                icon: Vpn.connected ? "\u{f099d}" : "\u{f099e}",
                on: Vpn.connected,
                more: "Show recent locations",
                run: () => Vpn.toggle(),
                children: (Vpn.recents ?? []).map(r => ({
                            name: `vpn:${r.code}`,
                            title: r.label,
                            icon: "\u{f034e}",
                            state: r.code === Vpn.code && Vpn.connected ? "Connected" : "Recent",
                            verb: "Connect here",
                            run: () => Vpn.pick(r.code)
                        }))
            });
        if (sink) {
            found.push({
                name: "Sound output",
                sub: sink.description || sink.name,
                keywords: "audio speaker headphones sink device",
                icon: "\u{f04c3}",
                state: `${outputs.length} ${outputs.length === 1 ? "device" : "devices"}`,
                expands: true,
                more: "Show outputs",
                run: () => {},
                children: outputs.map(o => ({
                            name: `output:${o.name}`,
                            title: o.description || o.name,
                            icon: "\u{f04c3}",
                            state: o === sink ? "Current" : "",
                            on: o === sink ? true : undefined,
                            verb: "Use this output",
                            run: () => Pipewire.preferredDefaultAudioSink = o
                        }))
            });
            found.push({
                name: "Mute sound",
                sub: `Volume ${Math.round((sink.audio?.volume ?? 0) * 100)}%`,
                keywords: "audio volume silence speaker toggle",
                icon: sink.audio?.muted ? "\u{f075f}" : "\u{f057e}",
                on: sink.audio?.muted ?? false,
                run: () => {
                    if (root.sink?.audio)
                        root.sink.audio.muted = !root.sink.audio.muted;
                }
            });
        }
        if (source)
            found.push({
                name: "Mute microphone",
                sub: source.description || source.name,
                keywords: "audio mic input toggle",
                icon: source.audio?.muted ? "\u{f036d}" : "\u{f036c}",
                on: source.audio?.muted ?? false,
                run: () => {
                    if (root.source?.audio)
                        root.source.audio.muted = !root.source.audio.muted;
                }
            });
        return found.map(tagged);
    }

    function tagged(item: var): var {
        return Object.assign({
            kind: "control",
            tag: item.state ?? (item.on === undefined ? root.tag : item.on ? "On" : "Off")
        }, item, item.children ? {
            children: item.children.map(tagged)
        } : {});
    }

    function results(query: string): var {
        const q = query.trim().toLowerCase();
        return entries.filter(e => !q || e.name.toLowerCase().includes(q));
    }

    function activate(item: var): void {
        item.run();
    }

    function actions(item: var): var {
        if (item.expands)
            return [];
        return [
            {
                label: item.verb ?? (item.on ? "Turn off" : "Turn on"),
                stay: true,
                run: item.run
            }
        ];
    }

    PwObjectTracker {
        objects: [root.sink, root.source].filter(Boolean)
    }
}
