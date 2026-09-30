pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    readonly property int usageGap: 60000
    readonly property int slowGap: 300000

    property var claude: blank("checking…")
    property var codex: blank("checking…")
    property var codexCatalog: []
    property var claudeServers: []
    property var codexServers: []

    property real usageChecked: 0
    property real slowChecked: 0
    property int codexAwaited: 0

    function blank(note: string): var {
        return {
            plan: "",
            note,
            windows: []
        };
    }

    function refresh(): void {
        const now = Date.now();
        if (!claudeProbe.running && now - usageChecked >= usageGap) {
            usageChecked = now;
            claudeProbe.running = true;
        }
        if (now - slowChecked < slowGap)
            return;
        slowChecked = now;
        if (!codexProbe.running)
            codexProbe.running = true;
        if (!claudeServerProbe.running)
            claudeServerProbe.running = true;
    }

    function readClaudeServers(text: string): void {
        const servers = [];
        for (const line of text.split("\n")) {
            const found = line.match(/^(.+?): .* - \S+ (.+)$/);
            if (!found)
                continue;
            const status = found[2].trim().toLowerCase();
            servers.push({
                name: found[1],
                status,
                tone: status === "connected" ? "ok" : status.includes("auth") ? "warn" : "bad"
            });
        }
        claudeServers = servers;
    }

    function readCodexServers(data: var): void {
        codexServers = data.map(server => {
            const status = server.authStatus === "notLoggedIn" ? "needs authentication" : String(server.runtimeStatus ?? "configured").replace(/([A-Z])/g, " $1").toLowerCase();
            return {
                name: server.name,
                status,
                tone: status === "connected" || status === "configured" ? "ok" : status.includes("auth") || status.includes("start") ? "warn" : "bad"
            };
        });
    }

    function spanLabel(minutes: var): string {
        if (!minutes)
            return "limit";
        return minutes >= 1440 ? `${Math.round(minutes / 1440)}d` : `${Math.round(minutes / 60)}h`;
    }

    function readClaude(text: string): void {
        let d;
        try {
            d = JSON.parse(text);
        } catch (e) {
            return;
        }
        const windows = (d.usage?.limits ?? []).map(l => {
            const session = l.group === "session";
            const model = l.scope?.model?.display_name;
            return {
                label: session ? "5h" : model ? `7d ${model}` : "7d",
                used: l.percent / 100,
                resets: l.resets_at ? Date.parse(l.resets_at) : 0,
                span: (session ? 5 : 168) * 3600000
            };
        });
        claude = {
            plan: d.plan ?? "",
            note: windows.length > 0 ? "" : "no limits reported",
            windows
        };
    }

    function readCodex(line: string): void {
        let m;
        try {
            m = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (m.id !== 2 && m.id !== 3 && m.id !== 4)
            return;
        if (--codexAwaited === 0) {
            codexTimeout.stop();
            codexProbe.running = false;
        }
        if (m.id === 4)
            readCodexServers(m.result?.data ?? []);
        else if (m.id === 3)
            readCodexCatalog(m.result?.data ?? []);
        else if (m.error)
            codex = blank(String(m.error.message).includes("authentication") ? "not signed in · run codex login" : String(m.error.message));
        else
            readCodexLimits(m.result?.rateLimits ?? {});
    }

    function readCodexCatalog(data: var): void {
        if (data.length > 0)
            codexCatalog = data.filter(entry => !entry.hidden).map(entry => ({
                        model: entry.model,
                        preferred: entry.isDefault === true,
                        efforts: (entry.supportedReasoningEfforts ?? []).map(option => option.reasoningEffort)
                    }));
    }

    function readCodexLimits(snap: var): void {
        const windows = [snap.primary, snap.secondary].filter(w => w).map(w => ({
                    label: spanLabel(w.windowDurationMins),
                    used: w.usedPercent / 100,
                    resets: (w.resetsAt ?? 0) * 1000,
                    span: (w.windowDurationMins ?? 0) * 60000
                }));
        codex = {
            plan: snap.planType ?? "",
            note: windows.length > 0 ? "" : "no limits reported",
            windows
        };
    }

    function ask(id: int, method: string, params: var): void {
        codexProbe.write(JSON.stringify({
            id,
            method,
            params
        }) + "\n");
    }

    Process {
        id: claudeProbe

        command: ["bash", `${Quickshell.shellDir}/scripts/claude-usage.sh`]

        stdout: StdioCollector {
            onStreamFinished: root.readClaude(text)
        }

        onExited: code => {
            if (code === 0)
                return;
            root.claude = Object.assign({}, root.claude, {
                note: code === 2 ? "not signed in · run claude" : code === 3 ? "token expired · renews when Claude next runs" : "usage unavailable"
            });
        }
    }

    Process {
        id: claudeServerProbe

        command: ["sh", "-c", Agent.pathPrefix + 'mkdir -p "$0" && cd "$0" && exec claude mcp list', Agent.workDir]

        stdout: StdioCollector {
            onStreamFinished: root.readClaudeServers(text)
        }
    }

    Process {
        id: codexProbe

        stdinEnabled: true
        command: ["sh", "-c", Agent.pathPrefix + "exec codex app-server"]

        onStarted: {
            root.ask(1, "initialize", {
                clientInfo: {
                    name: "quickshell",
                    title: "Quickshell",
                    version: "1"
                }
            });
            write(JSON.stringify({
                method: "initialized"
            }) + "\n");
            root.ask(2, "account/rateLimits/read", undefined);
            root.ask(3, "model/list", {});
            root.ask(4, "mcpServerStatus/list", {});
            root.codexAwaited = 3;
            codexTimeout.restart();
        }

        stdout: SplitParser {
            onRead: line => root.readCodex(line)
        }

        onExited: code => {
            if (code === 127)
                root.codex = root.blank("not installed");
        }
    }

    Timer {
        id: codexTimeout

        interval: 15000
        onTriggered: {
            codexProbe.running = false;
            root.codex = Object.assign({}, root.codex, {
                note: "usage unavailable"
            });
        }
    }
}
