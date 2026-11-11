#!/usr/bin/env python3

import glob
import json
import os
import re
import select
import subprocess
import sys
import time

RATE = 1.0
SAMPLES = 40
FLOOR = 102400
OPEN = 2.0
CLOSED = 5.0
GAP = 1.0
SETTLE = 0.5
TICK = os.sysconf("SC_CLK_TCK")
PAGE = os.sysconf("SC_PAGE_SIZE")
PF_KTHREAD = 0x00200000
TOP = 8

ENGINES = {
    "rcs": "Render",
    "render": "Render",
    "gfx": "Render",
    "vcs": "Video",
    "vecs": "Video",
    "video": "Video",
    "video-enhance": "Video",
    "dec": "Video",
    "enc": "Video",
    "ccs": "Compute",
    "compute": "Compute",
    "bcs": "Copy",
    "copy": "Copy",
    "dma": "Copy",
}
ENGINE_ORDER = ["Render", "Video", "Compute", "Copy"]

THROTTLE = {
    "pl1": "PL1 power",
    "pl2": "PL2 power",
    "pl4": "PL4 power",
    "prochot": "PROCHOT",
    "ratl": "RATL",
    "thermal": "thermal",
    "vr_tdc": "VR current",
    "vr_thermalert": "VR thermal",
}

PID = re.compile(r"pid=(\d+)")
ACKED = re.compile(r"bytes_acked:(\d+)")
RECEIVED = re.compile(r"bytes_received:(\d+)")
UNITS = {"KiB": 1024, "MiB": 1024**2, "GiB": 1024**3}


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def num(path, default=0):
    try:
        return int(read(path))
    except ValueError:
        return default


def natural(text):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", text)]


def cpu_list(spec):
    out = []
    for part in spec.split(","):
        if not part:
            continue
        lo, _, hi = part.partition("-")
        out.extend(range(int(lo), int(hi or lo) + 1))
    return out


def size(value):
    parts = value.split()
    if not parts:
        return 0
    try:
        return int(parts[0]) * UNITS.get(parts[1] if len(parts) > 1 else "", 1)
    except ValueError:
        return 0


def loopback(addr):
    host = addr.rsplit(":", 1)[0].strip("[]")
    return host.startswith("127.") or host == "::1" or host.startswith("::ffff:127.")


def counters(table):
    out = {}
    for line in read(table).splitlines()[2:]:
        name, _, rest = line.partition(":")
        fields = rest.split()
        if len(fields) >= 9:
            out[name.strip()] = (int(fields[0]), int(fields[8]))
    return out


def default_iface():
    best = None
    for line in read("/proc/net/route").splitlines()[1:]:
        f = line.split()
        if len(f) > 7 and f[1] == "00000000" and f[7] == "00000000":
            metric = int(f[6])
            if best is None or metric < best[0]:
                best = (metric, f[0])
    return best[1] if best else ""


class Cpu:
    def __init__(self):
        model = ""
        for line in read("/proc/cpuinfo").splitlines():
            if line.startswith("model name"):
                model = line.split(":", 1)[1]
                break
        model = re.sub(r"\((R|TM)\)|\bCPU\b|@.*$", "", model)
        self.model = re.sub(r"\s+", " ", model).strip()

        base = "/sys/devices/system/cpu"
        self.cpus = cpu_list(read(f"{base}/online")) or [
            int(d[3:]) for d in os.listdir(base) if re.fullmatch(r"cpu\d+", d)
        ]
        big = set(cpu_list(read("/sys/devices/cpu_core/cpus")))
        small = set(cpu_list(read("/sys/devices/cpu_atom/cpus")))
        top = {c: num(f"{base}/cpu{c}/cpufreq/cpuinfo_max_freq") for c in self.cpus}
        tiers = {top[c] for c in small}
        lowest = min(tiers, default=0)

        seen = {}
        self.cores = []
        for c in self.cpus:
            if c in big:
                kind = "P"
            elif c in small:
                kind = "LP" if len(tiers) > 1 and top[c] == lowest else "E"
            else:
                kind = "C"
            index = seen.get(kind, 0)
            seen[kind] = index + 1
            self.cores.append(
                {
                    "cpu": c,
                    "kind": kind,
                    "label": f"{kind}{index}",
                    "core": num(f"{base}/cpu{c}/topology/core_id", -1),
                    "freq": f"{base}/cpu{c}/cpufreq/scaling_cur_freq",
                }
            )
        self.prev = {}

    def stat(self):
        out = {}
        for line in read("/proc/stat").splitlines():
            if not line.startswith("cpu"):
                break
            parts = line.split()
            values = [int(v) for v in parts[1:9]]
            out[parts[0]] = (sum(values), values[3] + values[4])
        return out

    def usage(self, now, name):
        total, idle = now.get(name, (0, 0))
        was_total, was_idle = self.prev.get(name, (total, idle))
        span = total - was_total
        return round(1 - (idle - was_idle) / span, 3) if span > 0 else 0.0

    def sample(self, sensors):
        now = self.stat()
        cores = []
        freqs = []
        for core in self.cores:
            freq = num(core["freq"]) / 1e6
            freqs.append(freq)
            cores.append(
                {
                    "label": core["label"],
                    "kind": core["kind"],
                    "usage": self.usage(now, f"cpu{core['cpu']}"),
                    "freq": round(freq, 2),
                    "temp": sensors.core(core["core"]),
                }
            )
        load = read("/proc/loadavg").split()
        threads = (load[3] if len(load) > 3 else "0/0").partition("/")[2]
        out = {
            "usage": self.usage(now, "cpu"),
            "model": self.model,
            "cores": cores,
            "freq": round(sum(freqs) / len(freqs), 2) if freqs else 0,
            "load": [float(v) for v in load[:3]],
            "threads": int(threads or 0),
            "temp": sensors.package(),
            "governor": read("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"),
            "epp": read("/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference"),
        }
        self.prev = now
        return out


class Sensors:
    def __init__(self):
        self.cores = {}
        self.pkg = ""
        self.temps = []
        self.fans = []
        acpi = []
        named = []
        for hwmon in sorted(glob.glob("/sys/class/hwmon/hwmon*"), key=natural):
            name = read(f"{hwmon}/name")
            inputs = sorted(glob.glob(f"{hwmon}/temp*_input"), key=natural)
            labels = {p: read(p[: -len("_input")] + "_label") for p in inputs}
            fans = sorted(glob.glob(f"{hwmon}/fan*_input"), key=natural)
            (acpi if name == "acpi_fan" else self.fans).extend(fans)
            if name == "coretemp":
                for path, label in labels.items():
                    if label.startswith("Core "):
                        self.cores[int(label[5:])] = path
                    elif label.startswith("Package") and not self.pkg:
                        self.pkg = path
            elif name in ("k10temp", "zenpower"):
                pick = [p for p, l in labels.items() if l in ("Tdie", "Tctl")]
                if pick and not self.pkg:
                    self.pkg = pick[0]
            elif not inputs or name in ("acpitz", "acpi_fan"):
                continue
            elif name == "nvme":
                named.append(("SSD", inputs[0]))
            elif name in ("spd5118", "jc42"):
                named.append(("RAM", inputs[0]))
            elif name.startswith("iwlwifi") or name.startswith("mt7"):
                named.append(("Wi-Fi", inputs[0]))
            elif name in ("amdgpu", "xe", "i915", "nouveau"):
                named.append(("GPU", inputs[0]))
            elif name == "cros_ec":
                named.extend(("Battery", p) for p, l in labels.items() if l.startswith("battery"))
            else:
                named.append((name, inputs[0]))
        if not self.fans:
            self.fans = acpi
        totals = {}
        for label, _ in named:
            totals[label] = totals.get(label, 0) + 1
        seen = {}
        for label, path in named:
            seen[label] = seen.get(label, 0) + 1
            self.temps.append((f"{label} {seen[label]}" if totals[label] > 1 else label, path))
        if self.pkg:
            self.temps.insert(0, ("CPU", self.pkg))

    def core(self, core_id):
        path = self.cores.get(core_id)
        return num(path) // 1000 if path else None

    def package(self):
        return num(self.pkg) // 1000 if self.pkg else None

    def sample(self):
        temps = [{"name": n, "value": num(p) // 1000} for n, p in self.temps]
        fans = [rpm for rpm in (num(p) for p in self.fans) if rpm > 0]
        return [t for t in temps if t["value"] > 0], fans


class Gpu:
    def __init__(self, card):
        dev = f"{card}/device"
        self.driver = os.path.basename(os.path.realpath(f"{dev}/driver"))
        self.slot = os.path.basename(os.path.realpath(dev))
        self.name = self.lookup() or self.driver
        self.gts = []
        self.busy = ""
        self.vram = None
        if self.driver == "xe":
            for gt in sorted(glob.glob(f"{dev}/tile*/gt*"), key=natural):
                media = read(f"{gt}/gtidle/name").endswith("-mc")
                self.gts.append(
                    {
                        "media": media,
                        "idle": f"{gt}/gtidle/idle_residency_ms",
                        "act": f"{gt}/freq0/act_freq",
                        "max": f"{gt}/freq0/max_freq",
                        "throttle": (f"{gt}/freq0/throttle", "reason_", "status"),
                    }
                )
        elif self.driver == "i915":
            for gt in sorted(glob.glob(f"{card}/gt/gt*"), key=natural):
                self.gts.append(
                    {
                        "media": not gt.endswith("gt0"),
                        "idle": f"{gt}/rc6_residency_ms",
                        "act": f"{gt}/rps_act_freq_mhz",
                        "max": f"{gt}/rps_max_freq_mhz",
                        "throttle": (gt, "throttle_reason_", "throttle_reason_status"),
                    }
                )
        elif self.driver == "amdgpu":
            self.busy = f"{dev}/gpu_busy_percent"
            self.vram = (f"{dev}/mem_info_vram_used", f"{dev}/mem_info_vram_total")
        self.prev = {}

    def lookup(self):
        try:
            out = subprocess.run(["lspci", "-mm", "-s", self.slot], capture_output=True, text=True, timeout=2).stdout
        except (OSError, subprocess.SubprocessError):
            return ""
        fields = re.findall(r'"([^"]*)"', out)
        if len(fields) < 3:
            return ""
        vendor = fields[1].split()[0] if fields[1] else ""
        model = re.search(r"\[([^\]]+)\]", fields[2])
        return f"{vendor} {model.group(1) if model else fields[2]}".strip()

    def throttled(self, spec):
        folder, prefix, status = spec
        if num(f"{folder}/{status}") != 1:
            return []
        reasons = []
        for path in sorted(glob.glob(f"{folder}/{prefix}*")):
            key = os.path.basename(path)[len(prefix):]
            if key in THROTTLE and num(path) == 1:
                reasons.append(THROTTLE[key])
        return reasons

    def sample(self, now_ms, engines, memory):
        out = {
            "name": self.name,
            "driver": self.driver,
            "engines": [{"name": e, "busy": round(min(1, engines.get(e, 0)), 3)} for e in ENGINE_ORDER if e in engines or e == "Render"],
            "mem": memory,
            "freq": 0,
            "maxFreq": 0,
            "awake": None,
            "media": None,
            "throttle": [],
        }
        for gt in self.gts:
            idle = num(gt["idle"])
            was = self.prev.get(gt["idle"])
            self.prev[gt["idle"]] = (idle, now_ms)
            awake = None
            if was and now_ms > was[1]:
                awake = round(max(0.0, min(1.0, 1 - (idle - was[0]) / (now_ms - was[1]))), 3)
            if gt["media"]:
                out["media"] = awake
            else:
                out["awake"] = awake
                out["freq"] = num(gt["act"])
                out["maxFreq"] = num(gt["max"])
                out["throttle"] = self.throttled(gt["throttle"])
        if self.busy:
            out["engines"][0]["busy"] = round(num(self.busy) / 100, 3)
        if self.vram:
            out["vram"] = num(self.vram[0])
            out["vramTotal"] = num(self.vram[1])
        return out


class Procs:
    def __init__(self):
        self.prev = {}
        self.keys = {}
        self.drm = {}
        self.clients = {}
        self.rescan = 0
        self.primed = False

    def key(self, ident, comm, kthread):
        hit = self.keys.get(ident)
        if hit and hit[1] == comm:
            return hit[0]
        if kthread:
            key = "k:" + comm.split("/")[0]
        else:
            try:
                key = os.readlink(f"/proc/{ident[0]}/exe")
            except OSError:
                key = "c:" + comm
        self.keys[ident] = (key, comm)
        return key

    def scan(self, span):
        rows = {}
        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            try:
                with open(f"/proc/{entry}/stat", "rb") as f:
                    raw = f.read()
                with open(f"/proc/{entry}/statm", "rb") as f:
                    statm = f.read().split()
            except OSError:
                continue
            close = raw.rfind(b")")
            comm = raw[raw.find(b"(") + 1 : close].decode(errors="replace")
            f = raw[close + 2 :].split()
            if len(f) < 22:
                continue
            pid = int(entry)
            start = int(f[19])
            kthread = bool(int(f[6]) & PF_KTHREAD)
            ident = (pid, start)
            ticks = int(f[11]) + int(f[12])
            rows[pid] = {
                "ident": ident,
                "ppid": int(f[1]),
                "comm": comm,
                "kthread": kthread,
                "ticks": ticks,
                "mem": max(0, int(statm[1]) - int(statm[2])) * PAGE if len(statm) > 2 else 0,
                "key": self.key(ident, comm, kthread),
            }

        current = {}
        for row in rows.values():
            ident = row["ident"]
            current[ident] = row["ticks"]
            if ident in self.prev:
                used = row["ticks"] - self.prev[ident]
            else:
                used = row["ticks"] if self.primed else 0
            row["cpu"] = max(0.0, used / (span * TICK) * 100) if span > 0 else 0.0
        self.prev = current
        self.primed = True
        self.keys = {i: k for i, k in self.keys.items() if i in current}

        lead = {}

        def leader(pid):
            trail = []
            while pid not in lead:
                row = rows[pid]
                parent = rows.get(row["ppid"])
                if parent is None or parent["key"] != row["key"]:
                    lead[pid] = pid
                    break
                trail.append(pid)
                pid = row["ppid"]
            for step in trail:
                lead[step] = lead[pid]
            return lead[pid]

        for pid, row in rows.items():
            if row["kthread"]:
                row["name"] = row["key"][2:]
                continue
            head = rows[leader(pid)]
            name = head["comm"]
            exe = os.path.basename(head["key"]) if not head["key"].startswith("c:") else ""
            if len(name) == 15 and exe.startswith(name):
                name = exe
            row["name"] = name
        return rows

    def drm_fds(self, pid):
        fds = []
        try:
            entries = os.listdir(f"/proc/{pid}/fd")
        except OSError:
            return fds
        for fd in entries:
            try:
                if os.readlink(f"/proc/{pid}/fd/{fd}").startswith("/dev/dri/"):
                    fds.append(fd)
            except OSError:
                pass
        return fds

    def gpu(self, rows, now_ns):
        self.rescan -= 1
        if self.rescan <= 0:
            self.drm = {}
            self.rescan = 5
        alive = {row["ident"] for row in rows.values()}
        self.drm = {i: fds for i, fds in self.drm.items() if i in alive}

        engines = {}
        memory = {}
        seen = {}
        for pid, row in rows.items():
            if row["kthread"]:
                continue
            fds = self.drm.get(row["ident"])
            if fds is None:
                fds = self.drm[row["ident"]] = self.drm_fds(pid)
            row["gpu"] = 0.0
            row["gpuMem"] = 0
            for fd in fds:
                info = {}
                try:
                    with open(f"/proc/{pid}/fdinfo/{fd}") as f:
                        for line in f:
                            k, _, v = line.partition(":")
                            info[k] = v.strip()
                except OSError:
                    continue
                cid = info.get("drm-client-id")
                if cid is None:
                    continue
                pdev = info.get("drm-pdev", "")
                client = (pdev, cid)
                if client in seen:
                    continue
                stamps = {}
                for k, v in info.items():
                    if k.startswith("drm-cycles-"):
                        raw = k[len("drm-cycles-"):]
                        total = info.get(f"drm-total-cycles-{raw}")
                        if total:
                            stamps[raw] = (size(v), size(total))
                    elif k.startswith("drm-engine-") and not k.startswith("drm-engine-capacity-"):
                        stamps[k[len("drm-engine-"):]] = (size(v), now_ns)
                was = self.clients.get(client, {})
                share = 0.0
                for raw, (busy, total) in stamps.items():
                    if raw not in was or total <= was[raw][1]:
                        continue
                    capacity = max(1, size(info.get(f"drm-engine-capacity-{raw}", "1")))
                    fraction = max(0.0, (busy - was[raw][0]) / (total - was[raw][1]) / capacity)
                    share = max(share, fraction)
                    bucket = engines.setdefault(pdev, {})
                    bucket[raw] = bucket.get(raw, 0) + fraction
                seen[client] = stamps
                resident = sum(size(v) for k, v in info.items() if k.startswith("drm-resident-"))
                memory[pdev] = memory.get(pdev, 0) + resident
                row["gpu"] += share
                row["gpuMem"] += resident
        self.clients = seen

        merged = {}
        for pdev, raws in engines.items():
            out = merged.setdefault(pdev, {})
            for raw, value in raws.items():
                label = ENGINES.get(raw, raw.title())
                out[label] = max(out.get(label, 0), value)
        return merged, memory


class Net:
    def __init__(self):
        self.sockets = None
        self.devices = {}

    def ss(self):
        try:
            out = subprocess.run(
                ["ss", "-tinpHn", "state", "established"], capture_output=True, text=True, timeout=2
            ).stdout
        except (OSError, subprocess.SubprocessError):
            return {}
        socks = {}
        key = None
        for line in out.splitlines():
            if not line.strip():
                continue
            if line[0] not in " \t":
                parts = line.split()
                key = None
                if len(parts) < 4 or (loopback(parts[2]) and loopback(parts[3])):
                    continue
                key = (parts[2], parts[3])
                match = PID.search(line)
                socks[key] = [int(match.group(1)) if match else None, 0, 0]
            elif key:
                acked = ACKED.search(line)
                received = RECEIVED.search(line)
                socks[key][1] = int(acked.group(1)) if acked else 0
                socks[key][2] = int(received.group(1)) if received else 0
        return socks

    def sample(self, span, rows):
        devices = counters("/proc/net/dev")
        rates = {}
        for name, (rx, tx) in devices.items():
            was = self.devices.get(name)
            if was and span > 0:
                rates[name] = (max(0, rx - was[0]) / span, max(0, tx - was[1]) / span)
            else:
                rates[name] = (0.0, 0.0)
        self.devices = devices

        socks = self.ss()
        per = {}
        for key, (pid, sent, received) in socks.items():
            if self.sockets is None:
                continue
            was = self.sockets.get(key)
            up = sent - was[1] if was else sent
            down = received - was[2] if was else received
            if up <= 0 and down <= 0:
                continue
            row = rows.get(pid) if pid else None
            name = row["name"] if row else "system"
            entry = per.setdefault(name, [0, 0])
            entry[0] += max(0, down)
            entry[1] += max(0, up)
        self.sockets = socks

        iface = default_iface()
        rx, tx = rates.get(iface, (0.0, 0.0))
        procs = [{"name": n, "rx": round(d / span), "tx": round(u / span)} for n, (d, u) in per.items()] if span > 0 else []
        procs.sort(key=lambda p: p["rx"] + p["tx"], reverse=True)
        attributed_rx = sum(p["rx"] for p in procs)
        attributed_tx = sum(p["tx"] for p in procs)
        out = {
            "iface": iface,
            "rx": round(rx),
            "tx": round(tx),
            "procs": procs[:TOP],
            "other": {"rx": round(max(0, rx - attributed_rx)), "tx": round(max(0, tx - attributed_tx))},
            "ifaces": [
                {"name": n, "rx": round(r), "tx": round(t)}
                for n, (r, t) in sorted(rates.items(), key=lambda i: natural(i[0]))
                if n != "lo"
                and not n.startswith("veth")
                and read(f"/sys/class/net/{n}/operstate") in ("up", "unknown")
            ],
        }
        return out


def speed_text(rate):
    rate = int(rate)
    if rate >= 1048576:
        return f"{rate / 1048576:.1f} MB/s"
    if rate >= 1024:
        return f"{rate // 1024} KB/s"
    return f"{rate} B/s"


class Speed:
    def __init__(self):
        self.rx = [0] * SAMPLES
        self.tx = [0] * SAMPLES
        self.iface = ""
        self.prev = None

    def sample(self):
        iface = default_iface()
        if not iface:
            self.prev = None
            return {"iface": "", "rx": [], "tx": [], "down": "", "up": ""}
        rx, tx = counters("/proc/net/dev").get(iface, (0, 0))
        now = time.monotonic()
        down = up = 0
        if self.prev and self.iface == iface and now > self.prev[2]:
            span = now - self.prev[2]
            down = max(0, rx - self.prev[0]) / span
            up = max(0, tx - self.prev[1]) / span
        self.iface = iface
        self.prev = (rx, tx, now)
        self.rx = self.rx[1:] + [down]
        self.tx = self.tx[1:] + [up]
        peak = max(FLOOR, *self.rx, *self.tx)
        return {
            "iface": iface,
            "rx": [round(v / peak, 3) for v in self.rx],
            "tx": [round(v / peak, 3) for v in self.tx],
            "down": speed_text(down),
            "up": speed_text(up),
        }


class Disks:
    def __init__(self):
        skip = ("loop", "ram", "zram", "dm-", "sr", "md", "nbd")
        self.names = {d for d in os.listdir("/sys/block") if not d.startswith(skip)}
        self.prev = {}

    def sample(self, span):
        out = []
        now = {}
        for line in read("/proc/diskstats").splitlines():
            f = line.split()
            if len(f) > 9 and f[2] in self.names:
                now[f[2]] = (int(f[5]) * 512, int(f[9]) * 512)
        for name in sorted(now, key=natural):
            was = self.prev.get(name)
            r, w = now[name]
            if was and span > 0:
                out.append({"name": name, "read": round((r - was[0]) / span), "write": round((w - was[1]) / span)})
            else:
                out.append({"name": name, "read": 0, "write": 0})
        self.prev = now
        return out


def memory():
    m = {}
    for line in read("/proc/meminfo").splitlines():
        k, _, v = line.partition(":")
        parts = v.split()
        if parts:
            m[k] = int(parts[0]) * 1024
    total = m.get("MemTotal", 0)
    free = m.get("MemFree", 0)
    used = total - m.get("MemAvailable", free)
    swap = m.get("SwapTotal", 0)
    return {
        "total": total,
        "used": used,
        "cache": max(0, total - used - free),
        "free": free,
        "swapTotal": swap,
        "swapUsed": swap - m.get("SwapFree", 0),
        "zram": "zram" in read("/proc/swaps"),
    }


def disk():
    try:
        st = os.statvfs("/")
    except OSError:
        return 0.0
    return round(1 - st.f_bfree / st.f_blocks, 3) if st.f_blocks else 0.0


def uptime():
    try:
        return int(float(read("/proc/uptime").split()[0]))
    except (IndexError, ValueError):
        return 0


def power():
    base = "/sys/class/power_supply"
    watts = 0.0
    status = ""
    ac = None
    found = False
    for name in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        path = f"{base}/{name}"
        kind = read(f"{path}/type")
        if kind == "Mains":
            ac = ac or read(f"{path}/online") == "1"
        elif kind == "Battery" and read(f"{path}/scope") != "Device":
            found = True
            draw = abs(num(f"{path}/power_now"))
            if not draw:
                draw = abs(num(f"{path}/current_now")) * num(f"{path}/voltage_now") / 1e6
            watts += draw / 1e6
            status = status or read(f"{path}/status")
    return {"battery": found, "watts": round(watts, 1), "status": status, "ac": bool(ac)}


class Monitor:
    def __init__(self):
        self.cpu = Cpu()
        self.sensors = Sensors()
        self.gpus = [Gpu(c) for c in sorted(glob.glob("/sys/class/drm/card[0-9]*"), key=natural) if re.fullmatch(r"card\d+", os.path.basename(c))]
        self.procs = Procs()
        self.net = Net()
        self.disks = Disks()
        self.last = time.monotonic()

    def sample(self):
        now = time.monotonic()
        span = now - self.last
        self.last = now
        rows = self.procs.scan(span)
        engines, gmem = self.procs.gpu(rows, time.monotonic_ns())

        groups = {}
        for row in rows.values():
            g = groups.get(row["name"])
            if g is None:
                g = groups[row["name"]] = {"name": row["name"], "count": 0, "cpu": 0.0, "mem": 0, "gpu": 0.0, "gpuMem": 0}
            g["count"] += 1
            g["cpu"] += row["cpu"]
            g["mem"] += row["mem"]
            g["gpu"] += row.get("gpu", 0.0)
            g["gpuMem"] += row.get("gpuMem", 0)
        for g in groups.values():
            g["cpu"] = round(g["cpu"], 1)
            g["gpu"] = round(min(1.0, g["gpu"]), 3)
        values = list(groups.values())

        cpu = self.cpu.sample(self.sensors)
        temps, fans = self.sensors.sample()
        now_ms = time.monotonic() * 1000
        return {
            "cpu": cpu,
            "net": self.net.sample(span, rows),
            "count": len(rows),
            "byCpu": sorted(values, key=lambda g: (g["cpu"], g["mem"]), reverse=True)[:TOP],
            "byMem": sorted(values, key=lambda g: g["mem"], reverse=True)[:TOP],
            "byGpu": [g for g in sorted(values, key=lambda g: (g["gpu"], g["gpuMem"]), reverse=True) if g["gpu"] >= 0.001 or g["gpuMem"] > 0][:TOP],
            "gpus": [gpu.sample(now_ms, engines.get(gpu.slot, {}), gmem.get(gpu.slot, 0)) for gpu in self.gpus],
            "temps": temps,
            "fans": fans,
            "temp": cpu["temp"] if cpu["temp"] is not None else temps[0]["value"] if temps else 0,
            "mem": memory(),
            "power": power(),
            "disks": self.disks.sample(span),
            "disk": disk(),
            "uptime": uptime(),
        }


def emit(payload):
    print(json.dumps(payload, separators=(",", ":")), flush=True)


def main():
    monitor = Monitor()
    speed = Speed()
    monitor.sample()
    emit({"speed": speed.sample()})
    interval = OPEN if len(sys.argv) > 1 and sys.argv[1] == "open" else CLOSED
    now = time.monotonic()
    due = now + SETTLE
    tick = now + RATE
    pending = b""
    watching = True
    while True:
        now = time.monotonic()
        if now >= tick:
            emit({"speed": speed.sample()})
            tick = max(tick + RATE, now + RATE / 2)
            continue
        if now >= due:
            emit(monitor.sample())
            due = time.monotonic() + interval
            continue
        left = min(due, tick) - now
        if not watching:
            time.sleep(left)
            continue
        ready, _, _ = select.select([0], [], [], left)
        if not ready:
            continue
        chunk = os.read(0, 1024)
        if not chunk:
            watching = False
            continue
        pending += chunk
        *lines, pending = pending.split(b"\n")
        for line in lines:
            state = line.strip()
            if state == b"open" and interval != OPEN:
                interval = OPEN
                due = min(due, max(time.monotonic(), monitor.last + GAP))
            elif state == b"closed":
                interval = CLOSED


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        sys.exit(0)
