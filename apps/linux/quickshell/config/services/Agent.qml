pragma Singleton

import QtQuick
import Quickshell
import qs.services

Singleton {
    id: root

    readonly property var backends: ({
            claude,
            codex
        })
    readonly property var providers: Object.keys(backends)
    readonly property string provider: providers.includes(AgentStore.provider) ? AgentStore.provider : "claude"
    readonly property var backend: backends[provider]
    readonly property string label: backend.label

    readonly property bool available: backend.available
    readonly property bool running: backend.running
    readonly property bool shown: Panels.controls && Panels.controlsTab === "agent"

    readonly property string workDir: `${AgentStore.stateDir}/agent`

    readonly property var models: backend.models
    readonly property var efforts: backend.efforts
    readonly property var modes: backend.modes
    readonly property string model: AgentStore.setup.model
    readonly property string effort: AgentStore.setup.effort
    readonly property string mode: modes.some(m => m.id === AgentStore.setup.mode) ? AgentStore.setup.mode : "ask"
    readonly property string modeNote: backend.note
    readonly property string setup: `${model}|${effort}|${mode}`
    readonly property bool stale: runningSetup !== setup
    readonly property int idleMinutes: 15

    property bool busy: false
    property bool thinking: false
    property int pendingApprovals: 0
    property string activeId: ""

    readonly property string pathPrefix: 'export PATH="$HOME/.local/bin:$PATH"; '

    readonly property string sessionId: AgentStore.last
    readonly property var sessions: AgentStore.sessions
    property string runningSetup: ""

    property real contextUsed: -1
    property real contextMax: 0
    property string spend: ""

    signal optionKey(int number)
    signal submitKey
    signal navKey(int delta)
    signal enterKey
    signal queueReturned(string text)

    readonly property string systemPrompt: "You are running inside a Quickshell side panel on the user's Arch Linux + Hyprland desktop, acting as an agent for their operating system. Replies render in a narrow panel: keep them short. Their home directory is ~ and their dotfiles live in ~/dotfiles; your working directory is only a scratch space."

    readonly property ListModel messages: ListModel {}
    readonly property ListModel queue: ListModel {}

    property var approvals: ({})
    property int streamIndex: -1
    property bool restartQueued: false
    property string pendingTitle: ""
    property bool restored: false

    function start(): void {
        if (!available)
            return;
        if (backend.running) {
            if (backend.stopping)
                restartQueued = true;
            return;
        }
        runningSetup = setup;
        backend.start({
            model,
            effort,
            mode,
            sessionId
        });
    }

    function stop(): void {
        backend.stop();
    }

    function restore(): void {
        if (restored)
            return;
        restored = true;
        if (messages.count === 0 && sessionId)
            backend.restore(sessionId);
    }

    function send(text: string): void {
        const message = text.trim();
        if (!message)
            return;
        if (busy) {
            queue.append({
                text: message
            });
            return;
        }
        dispatch(message);
    }

    function dispatch(message: string): void {
        start();
        if (!sessionId)
            pendingTitle = message;
        const files = Attachments.take();
        const notes = files.map(f => f.note).join("\n");
        push("user", files.length > 0 ? `${message}\n${files.map(f => `󰋩 ${f.label}`).join("  ")}` : message, "", "", "");
        busy = true;
        idle.stop();
        backend.send(notes ? `${notes}\n\n${message}` : message, files);
    }

    function abort(): void {
        if (busy)
            backend.interrupt();
        returnQueue();
    }

    function removeQueued(index: int): void {
        if (index >= 0 && index < queue.count)
            queue.remove(index);
    }

    function popQueued(): string {
        if (queue.count === 0)
            return "";
        const text = queue.get(queue.count - 1).text;
        queue.remove(queue.count - 1);
        return text;
    }

    function returnQueue(): void {
        if (queue.count === 0)
            return;
        const texts = [];
        for (let i = 0; i < queue.count; i++)
            texts.push(queue.get(i).text);
        queue.clear();
        queueReturned(texts.join("\n\n"));
    }

    function clearView(): void {
        messages.clear();
        queue.clear();
        approvals = {};
        pendingApprovals = 0;
        activeId = "";
        busy = false;
        thinking = false;
        streamIndex = -1;
        contextUsed = -1;
        contextMax = 0;
        spend = "";
    }

    function setContext(used: real, max: real): void {
        contextUsed = used;
        contextMax = max;
    }

    function count(tokens: real): string {
        if (tokens >= 1000000)
            return `${(tokens / 1000000).toFixed(1)}M`;
        return tokens >= 1000 ? `${Math.round(tokens / 1000)}k` : String(tokens);
    }

    function reset(): void {
        stop();
        clearView();
        AgentStore.setLast("");
    }

    function resume(id: string): void {
        if (id === sessionId && messages.count > 0)
            return;
        stop();
        clearView();
        AgentStore.setProvider(sessions.find(s => s.id === id)?.provider ?? "claude");
        AgentStore.setLast(id);
        backend.restore(id);
    }

    function setProvider(name: string): bool {
        if (name === provider)
            return true;
        if (busy || pendingApprovals > 0 || !backends[name]?.available)
            return false;
        reset();
        AgentStore.setProvider(name);
        return true;
    }

    function cycleModel(): void {
        setModel(models[(models.indexOf(model) + 1) % models.length]);
    }

    function configure(key: string, value: string, options: var): bool {
        if (!options.includes(value))
            return false;
        AgentStore.configure(key, value);
        if (backend.running && !busy && pendingApprovals === 0)
            stop();
        return true;
    }

    function setModel(name: string): bool {
        if (!configure("model", name, models))
            return false;
        if (!efforts.includes(effort))
            AgentStore.configure("effort", "default");
        return true;
    }

    function setEffort(name: string): bool {
        return configure("effort", name, efforts);
    }

    function setMode(name: string): bool {
        return configure("mode", name, modes.map(m => m.id));
    }

    function forget(id: string): void {
        const session = sessions.find(s => s.id === id);
        if (!session)
            return;
        if (id === sessionId)
            reset();
        backends[session.provider ?? "claude"].forget(id);
        AgentStore.forget(id);
    }

    function lasting(requestId: string): bool {
        return approvals[requestId]?.lasting === true;
    }

    function settle(requestId: string, phase: string): bool {
        if (approvals[requestId] === undefined)
            return false;
        delete approvals[requestId];
        pendingApprovals = Math.max(pendingApprovals - 1, 0);
        Qt.callLater(refreshActive);
        setEntry(requestId, false, "phase", phase);
        return true;
    }

    function decide(requestId: string, verdict: string): void {
        if (verdict === "always" && !lasting(requestId))
            return;
        if (settle(requestId, verdict === "deny" ? "denied" : "allowed"))
            backend.decide(requestId, verdict);
    }

    function answer(requestId: string, answers: var): void {
        if (!settle(requestId, "answered"))
            return;
        setEntry(requestId, false, "text", Object.values(answers).join(" · "));
        backend.answer(requestId, answers);
    }

    function dropRequest(requestId: string): void {
        settle(requestId, "denied");
    }

    function decideLatest(verdict: string): void {
        if (activeId === "")
            return;
        if (verdict !== "deny" && approvals[activeId]?.role === "question")
            submitKey();
        else
            decide(activeId, verdict);
    }

    function refreshActive(): void {
        for (let i = 0; i < messages.count; i++) {
            const m = messages.get(i);
            if (m.phase === "pending" && (m.role === "approval" || m.role === "question")) {
                activeId = m.callId;
                return;
            }
        }
        activeId = "";
    }

    function push(role: string, text: string, detail: string, phase: string, callId: string): void {
        messages.append({
            role,
            text,
            detail,
            phase,
            callId
        });
    }

    function setEntry(id: string, tool: bool, key: string, value: string): void {
        for (let i = messages.count - 1; i >= 0; i--) {
            const m = messages.get(i);
            if (m.callId === id && (m.role === "tool") === tool) {
                messages.setProperty(i, key, value);
                return;
            }
        }
    }

    function addTool(id: string, name: string, detail: string): void {
        push("tool", name, detail, "running", id);
    }

    function markTool(id: string, failed: bool): void {
        setEntry(id, true, "phase", failed ? "error" : "done");
    }

    function setToolDetail(id: string, detail: string): void {
        setEntry(id, true, "detail", detail);
    }

    function beginText(): void {
        push("assistant", "", "", "", "");
        streamIndex = messages.count - 1;
    }

    function appendText(delta: string): void {
        if (streamIndex >= 0)
            messages.setProperty(streamIndex, "text", messages.get(streamIndex).text + delta);
    }

    function endText(text: string): void {
        if (text !== "" && streamIndex >= 0)
            messages.setProperty(streamIndex, "text", text);
        streamIndex = -1;
    }

    function request(requestId: string, role: string, title: string, detail: string, lasting: bool): void {
        approvals[requestId] = {
            role,
            lasting
        };
        pendingApprovals++;
        push(role, title, detail, "pending", requestId);
        notify(role === "question" ? "Has a question for you" : `Wants to run ${title}`);
        refreshActive();
    }

    function notify(body: string): void {
        if (!shown)
            Notices.show(label, body, "󰚩");
    }

    function sessionStarted(id: string): void {
        if (id !== sessionId)
            remember(id);
    }

    function remember(id: string): void {
        if (id === "")
            return;
        AgentStore.remember(id, pendingTitle);
        pendingTitle = "";
    }

    function rest(): void {
        idle.restart();
    }

    function turnEnded(failed: bool, message: string): void {
        busy = false;
        thinking = false;
        streamIndex = -1;
        if (failed)
            push("error", message, "", "", "");
        remember(sessionId);
        if (stale && pendingApprovals === 0)
            stop();
        if (queue.count > 0 && !failed) {
            const next = queue.get(0).text;
            queue.remove(0);
            Qt.callLater(dispatch, next);
        } else {
            returnQueue();
            notify(failed ? "Stopped with an error" : "Finished");
            idle.restart();
        }
    }

    function exited(from: var, code: int, crashed: bool): void {
        if (from !== backend)
            return;
        busy = restartQueued;
        thinking = false;
        streamIndex = -1;
        for (const id of Object.keys(approvals))
            setEntry(id, false, "phase", "denied");
        approvals = {};
        pendingApprovals = 0;
        activeId = "";
        idle.stop();
        if (crashed) {
            push("error", `${label} exited (${code})${from.error ? `: ${from.error}` : ""}. Send a message to restart.`, "", "", "");
            notify("Crashed");
            returnQueue();
        }
        if (restartQueued) {
            restartQueued = false;
            Qt.callLater(start);
        }
    }

    ClaudeBackend {
        id: claude

        host: root
    }

    CodexBackend {
        id: codex

        host: root
    }

    Timer {
        id: idle

        interval: root.idleMinutes * 60 * 1000
        onTriggered: {
            if (!root.busy && root.pendingApprovals === 0)
                root.stop();
        }
    }
}
