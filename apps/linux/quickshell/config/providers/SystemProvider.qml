pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.services
import qs.style

Singleton {
    id: root

    readonly property string id: "system"
    readonly property string label: "System"
    readonly property string tag: "System"
    readonly property bool fleeting: true
    readonly property string glyph: "\u{f04c5}"
    readonly property var battery: UPower.displayDevice

    readonly property var entries: {
        const found = [];
        const share = value => `${Math.round((value ?? 0) * 100)}%`;
        const load = value => value >= 0.9 ? Theme.red : value >= 0.7 ? Theme.orange : Theme.accent;
        const add = (name, icon, sub, keywords, more) => {
            if (sub)
                found.push(Object.assign({
                    kind: "stat",
                    name,
                    icon,
                    sub,
                    keywords: `system stats ${keywords}`,
                    children: []
                }, more ?? {}));
        };
        const detail = (title, value, more) => Object.assign({
                kind: "detail",
                name: `detail:${title}`,
                title,
                tag: value,
                icon: "\u{f0142}"
            }, more ?? {});
        const processes = (rows, metric, part, note) => {
            const top = Math.max(0.0001, ...(rows ?? []).map(part));
            return (rows ?? []).map(p => ({
                        kind: "process",
                        name: `process:${p.name}`,
                        process: p.name,
                        title: p.name,
                        sub: [note(p), p.count > 1 ? `${p.count} processes` : ""].filter(Boolean).join(" · "),
                        tag: metric(p),
                        meter: part(p) / top,
                        image: Quickshell.iconPath(DesktopEntries.heuristicLookup(p.name)?.icon ?? "", true),
                        icon: "\u{f018d}"
                    }));
        };

        if (battery?.isLaptopBattery) {
            const raw = battery.percentage ?? 0;
            const level = raw <= 1 ? raw : raw / 100;
            const charging = battery.state === UPowerDeviceState.Charging;
            const full = battery.state === UPowerDeviceState.FullyCharged;
            const left = duration(charging ? battery.timeToFull : battery.timeToEmpty);
            const parts = [share(level), full ? "Full" : charging ? "Charging" : Monitor.power.ac ? "Plugged in" : "On battery"];
            if (left && !full)
                parts.push(charging ? `${left} until full` : `${left} left`);
            const more = [];
            if (left && !full)
                more.push(detail(charging ? "Until full" : "Time left", left));
            if (Math.abs(battery.changeRate ?? 0) > 0.05)
                more.push(detail(charging ? "Charging at" : "Drawing", `${Math.abs(battery.changeRate).toFixed(1)} W`));
            if ((battery.energyCapacity ?? 0) > 0)
                more.push(detail("Charge", `${(battery.energy ?? 0).toFixed(1)} of ${battery.energyCapacity.toFixed(1)} Wh`));
            if (battery.healthSupported && (battery.healthPercentage ?? 0) > 0)
                more.push(detail("Health", `${Math.round(battery.healthPercentage)}%`, {
                    meter: battery.healthPercentage / 100
                }));
            if (Charge.supported)
                more.push(detail("Charge limit", `${Charge.limit}%`));
            add("Battery", charging || full ? "\u{f0084}" : "\u{f0079}", parts.join(" · "), "power charge", {
                meter: level,
                tint: level <= 0.1 ? Theme.red : level <= 0.2 ? Theme.yellow : Theme.green,
                children: more
            });
        }
        if (!Monitor.ready)
            return found;

        const usage = Monitor.cpu.usage ?? 0;
        add("CPU", "\u{f0ee0}", [share(usage), `${Monitor.temp}°C`, Monitor.cpu.model].filter(Boolean).join(" · "), "processor load usage processes top", {
            meter: usage,
            tint: load(usage),
            children: processes(Monitor.byCpu, p => `${Math.round(p.cpu)}%`, p => p.cpu, p => Monitor.size(p.mem))
        });
        add("Memory", "\u{f035b}", `${Monitor.size(Monitor.mem.used)} of ${Monitor.size(Monitor.mem.total)} · swap ${Monitor.size(Monitor.mem.swapUsed)}`, "ram swap", {
            meter: Monitor.memShare,
            tint: load(Monitor.memShare),
            children: processes(Monitor.byMem, p => Monitor.size(p.mem), p => p.mem, p => `${Math.round(p.cpu)}% CPU`)
        });
        Monitor.gpus.forEach((gpu, index) => {
            const engines = (gpu.engines ?? []).filter(e => (e.busy ?? 0) > 0.005);
            const busy = Math.max(0, ...(gpu.engines ?? []).map(e => e.busy ?? 0));
            add(Monitor.gpus.length > 1 ? `GPU ${index + 1}` : "GPU", "\u{f08ae}", [gpu.name, share(busy), gpu.mem ? Monitor.size(gpu.mem) : ""].filter(Boolean).join(" · "), "graphics vram video", {
                meter: busy,
                tint: load(busy),
                children: engines.map(e => detail(`${e.name} engine`, share(e.busy), {
                        meter: e.busy
                    })).concat(index === 0 ? processes(Monitor.byGpu, p => share(p.gpu), p => p.gpu, p => `${Monitor.size(p.gpuMem)} VRAM`) : [])
            });
        });
        add("Disk", "\u{f02ca}", `${share(Monitor.disk)} used`, "storage ssd space drive", {
            meter: Monitor.disk,
            tint: load(Monitor.disk),
            children: Monitor.disks.map(d => detail(d.name, `read ${Monitor.rate(d.read ?? 0)} · write ${Monitor.rate(d.write ?? 0)}`))
        });
        add("Network", Monitor.online ? "\u{f0928}" : "\u{f0200}", Monitor.online ? `${Monitor.speed.iface} · down ${Monitor.speed.down || "0"} · up ${Monitor.speed.up || "0"}` : "Offline", "wifi ethernet internet speed", {
            children: (Monitor.net.ifaces ?? []).map(i => detail(i.name, `down ${Monitor.rate(i.rx ?? 0)} · up ${Monitor.rate(i.tx ?? 0)}`))
        });
        add("Temperatures", "\u{f050f}", Monitor.temps.map(t => `${t.name} ${t.value}°`).join(" · "), "heat thermal sensors", {
            children: Monitor.temps.map(t => detail(t.name, `${t.value}°C`, {
                    meter: t.value / 100,
                    tint: Monitor.heat(t.value)
                }))
        });
        add("Fans", "\u{f0210}", Monitor.fans.length ? `${Monitor.fans.join(", ")} rpm` : "", "cooling rpm");
        add("Power draw", "\u{f140b}", Monitor.power.watts > 0 ? `${Monitor.power.watts.toFixed(1)} W · ${Monitor.power.status ?? ""}` : "", "watts energy");
        add("Uptime", "\u{f0150}", Monitor.uptimeText, "boot running since");
        add("Updates", "\u{f06b0}", Updates.known ? Updates.summary : "", "packages pacman aur upgrade");
        return found;
    }

    function duration(seconds: real): string {
        if (!seconds || seconds <= 0)
            return "";
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        return h > 0 ? `${h}h ${m}m` : `${m}m`;
    }

    function results(query: string): var {
        const q = query.trim().toLowerCase();
        return entries.filter(e => !q || e.name.toLowerCase().includes(q));
    }

    function words(item: var): string {
        if (item.kind === "process")
            return item.process;
        return item.kind === "detail" ? `${item.title}: ${item.tag}` : `${item.name}: ${item.sub}`;
    }

    function copy(item: var): void {
        Quickshell.execDetached(["wl-copy", words(item)]);
        Notices.show(item.title ?? item.name, "Copied", item.icon);
    }

    function activate(item: var): void {
        if (Panels.hidden)
            copy(item);
        else
            Panels.toggleDrawer("system");
    }

    function actions(item: var): var {
        const found = [
            {
                label: item.kind === "process" ? "Copy name" : "Copy",
                run: () => root.copy(item)
            }
        ];
        if (item.kind === "process")
            found.push({
                label: "Quit",
                run: () => Quickshell.execDetached(["pkill", "-x", "--", item.process])
            });
        if (!Panels.hidden)
            found.unshift({
                label: "Open system monitor",
                run: () => Panels.toggleDrawer("system")
            });
        return found;
    }
}
