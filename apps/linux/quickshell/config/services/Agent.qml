pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "agent.js" as AgentJs

Singleton {
    id: root

    readonly property bool available: claudePath !== ""
    readonly property bool running: proc.running
    readonly property bool shown: Panels.controls && Panels.controlsTab === "agent"

    readonly property string home: Quickshell.env("HOME")
    readonly property string workDir: `${AgentStore.stateDir}/agent`
    readonly property string transcriptDir: `${home}/.claude/projects/${workDir.replace(/[^A-Za-z0-9]/g, "-")}`

    readonly property var models: AgentStore.models
    readonly property int idleMinutes: 15

    property bool busy: false
    property bool thinking: false
    property string error: ""
    property int pendingApprovals: 0
    property string activeId: ""

    // Hyprland's session PATH may lack ~/.local/bin, where the native installer puts claude
    readonly property string pathPrefix: 'export PATH="$HOME/.local/bin:$PATH"; '
    property string claudePath: ""

    readonly property string sessionId: AgentStore.last
    readonly property var sessions: AgentStore.sessions
    readonly property string model: AgentStore.model
    property string runningModel: ""
    property real usage5h: -1
    property real usage7d: -1

    signal optionKey(int number)
    signal submitKey
    signal navKey(int delta)
    signal enterKey
    signal queueReturned(string text)

    readonly property string systemPrompt: "You are running inside a Quickshell side panel on the user's Arch Linux + Hyprland desktop, acting as an agent for their operating system. Replies render in a narrow panel: keep them short. Their home directory is ~ and their dotfiles live in ~/dotfiles; your working directory is only a scratch space."

    // each entry: role (user | assistant | tool | approval | question | error), text, detail, phase, callId
    readonly property ListModel messages: ListModel {}

    // messages typed while Claude is busy; each is sent when the current turn ends
    readonly property ListModel queue: ListModel {}

    property var approvals: ({})
    property int streamIndex: -1
    property int seq: 0
    property bool stopping: false
    property bool ready: false
    property bool restartQueued: false
    property var outbox: []
    property string pendingTitle: ""
    property bool restored: false

    function start(): void {
        if (!available)
            return;
        if (proc.running) {
            if (stopping)
                restartQueued = true;
            return;
        }
        error = "";
        stopping = false;
        const args = [claudePath, "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--permission-prompt-tool", "stdio", "--disallowedTools", "EnterPlanMode,ExitPlanMode,EnterWorktree,ExitWorktree", "--append-system-prompt", systemPrompt];
        if (model !== "default")
            args.push("--model", model);
        if (sessionId)
            args.push("--resume", sessionId);
        runningModel = model;
        proc.command = ["sh", "-c", pathPrefix + 'mkdir -p "$0" && cd "$0" && exec "$@"', workDir].concat(args);
        proc.running = true;
    }

    function stop(): void {
        if (!proc.running)
            return;
        stopping = true;
        ready = false;
        outbox = [];
        proc.running = false;
    }

    function restore(): void {
        if (restored)
            return;
        restored = true;
        if (messages.count === 0 && sessionId)
            transcript.path = `${transcriptDir}/${sessionId}.jsonl`;
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
        push("user", message, "", "", "");
        busy = true;
        idle.stop();
        write({
            type: "user",
            message: {
                role: "user",
                content: message
            }
        });
    }

    function abort(): void {
        if (busy)
            control({
                subtype: "interrupt"
            });
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
        AgentStore.setLast(id);
        transcript.path = "";
        transcript.path = `${transcriptDir}/${id}.jsonl`;
    }

    function cycleModel(): void {
        setModel(models[(models.indexOf(model) + 1) % models.length]);
    }

    function setModel(name: string): bool {
        if (!AgentStore.setModel(name))
            return false;
        if (proc.running && !busy && pendingApprovals === 0)
            stop();
        return true;
    }

    function decide(requestId: string, allow: bool): void {
        const input = approvals[requestId];
        if (input === undefined)
            return;
        delete approvals[requestId];
        pendingApprovals = Math.max(pendingApprovals - 1, 0);
        Qt.callLater(refreshActive);
        for (let i = messages.count - 1; i >= 0; i--) {
            if (messages.get(i).callId === requestId) {
                messages.setProperty(i, "phase", allow ? "allowed" : "denied");
                break;
            }
        }
        write({
            type: "control_response",
            response: {
                subtype: "success",
                request_id: requestId,
                response: allow ? {
                    behavior: "allow",
                    updatedInput: input
                } : {
                    behavior: "deny",
                    message: "The user denied this from the panel."
                }
            }
        });
    }

    function answer(requestId: string, answers: var): void {
        const input = approvals[requestId];
        if (input === undefined)
            return;
        delete approvals[requestId];
        pendingApprovals = Math.max(pendingApprovals - 1, 0);
        Qt.callLater(refreshActive);
        const summary = Object.values(answers).join(" · ");
        for (let i = messages.count - 1; i >= 0; i--) {
            if (messages.get(i).callId === requestId) {
                messages.setProperty(i, "phase", "answered");
                messages.setProperty(i, "text", summary);
                break;
            }
        }
        write({
            type: "control_response",
            response: {
                subtype: "success",
                request_id: requestId,
                response: {
                    behavior: "allow",
                    updatedInput: Object.assign({}, input, {
                        answers
                    })
                }
            }
        });
    }

    function decideLatest(allow: bool): void {
        if (activeId === "")
            return;
        if (allow && approvals[activeId]?.questions !== undefined)
            submitKey();
        else
            decide(activeId, allow);
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

    function control(request: var): void {
        write({
            type: "control_request",
            request_id: `qs-${++seq}`,
            request
        });
    }

    function write(payload: var): void {
        const line = JSON.stringify(payload) + "\n";
        if (ready)
            proc.write(line);
        else
            outbox = outbox.concat([line]);
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

    function findTool(id: string): int {
        for (let i = messages.count - 1; i >= 0; i--)
            if (messages.get(i).role === "tool" && messages.get(i).callId === id)
                return i;
        return -1;
    }

    function markTool(id: string, failed: bool): void {
        const i = findTool(id);
        if (i >= 0)
            messages.setProperty(i, "phase", failed ? "error" : "done");
    }

    function notify(body: string): void {
        if (!shown)
            Notices.show("Claude", body, "󰚩");
    }

    function remember(): void {
        if (sessionId) {
            AgentStore.remember(sessionId, pendingTitle);
            pendingTitle = "";
        }
    }

    function handleSubagent(event: var): void {
        if (event.type !== "assistant")
            return;
        const row = findTool(event.parent_tool_use_id);
        if (row < 0)
            return;
        for (const block of event.message?.content ?? [])
            if (block.type === "tool_use")
                messages.setProperty(row, "detail", `↳ ${block.name} ${AgentJs.describe(block.input)}`);
    }

    function handle(event: var): void {
        if (event.parent_tool_use_id) {
            handleSubagent(event);
            return;
        }
        switch (event.type) {
        case "system":
            if (event.subtype === "init" && event.session_id && event.session_id !== sessionId) {
                AgentStore.remember(event.session_id, pendingTitle);
                pendingTitle = "";
            }
            break;
        case "rate_limit_event":
            {
                const windows = event.rate_limit_info?.unifiedWindows ?? {};
                if (windows.five_hour?.utilization !== undefined)
                    usage5h = windows.five_hour.utilization;
                if (windows.seven_day?.utilization !== undefined)
                    usage7d = windows.seven_day.utilization;
                break;
            }
        case "stream_event":
            {
                const e = event.event ?? {};
                if (e.type === "content_block_start") {
                    const kind = e.content_block?.type;
                    thinking = kind === "thinking";
                    if (kind === "text") {
                        push("assistant", "", "", "", "");
                        streamIndex = messages.count - 1;
                    }
                } else if (e.type === "content_block_delta" && e.delta?.type === "text_delta" && streamIndex >= 0) {
                    messages.setProperty(streamIndex, "text", messages.get(streamIndex).text + e.delta.text);
                }
                break;
            }
        case "assistant":
            streamIndex = -1;
            for (const block of event.message?.content ?? [])
                if (block.type === "tool_use" && block.name !== "AskUserQuestion")
                    push("tool", block.name, AgentJs.describe(block.input), "running", block.id);
            break;
        case "user":
            for (const block of event.message?.content ?? [])
                if (block.type === "tool_result")
                    markTool(block.tool_use_id, block.is_error === true);
            break;
        case "control_request":
            if (event.request?.subtype === "can_use_tool") {
                const req = event.request;
                approvals[event.request_id] = req.input;
                pendingApprovals++;
                if (req.tool_name === "AskUserQuestion") {
                    push("question", "", JSON.stringify(req.input?.questions ?? []), "pending", event.request_id);
                    notify("Has a question for you");
                } else {
                    push("approval", req.display_name ?? req.tool_name, AgentJs.describe(req.input), "pending", event.request_id);
                    notify(`Wants to run ${req.display_name ?? req.tool_name}`);
                }
                refreshActive();
            }
            break;
        case "result":
            busy = false;
            thinking = false;
            streamIndex = -1;
            if (event.is_error)
                push("error", String(event.result ?? event.subtype ?? "Request failed"), "", "", "");
            remember();
            if (runningModel !== model && pendingApprovals === 0)
                stop();
            if (queue.count > 0 && !event.is_error) {
                const next = queue.get(0).text;
                queue.remove(0);
                Qt.callLater(dispatch, next);
            } else {
                returnQueue();
                notify(event.is_error ? "Stopped with an error" : "Finished");
                idle.restart();
            }
            break;
        }
    }

    Process {
        running: true
        command: ["sh", "-c", root.pathPrefix + "command -v claude"]

        stdout: StdioCollector {
            onStreamFinished: root.claudePath = text.trim()
        }
    }

    FileView {
        id: transcript

        onLoaded: {
            if (root.messages.count === 0)
                for (const e of AgentJs.replay(text()))
                    root.messages.append(e);
        }
    }

    Timer {
        id: idle

        interval: root.idleMinutes * 60 * 1000
        onTriggered: {
            if (!root.busy && root.pendingApprovals === 0)
                root.stop();
        }
    }

    Process {
        id: proc

        stdinEnabled: true

        onStarted: {
            root.ready = true;
            for (const line of root.outbox)
                proc.write(line);
            root.outbox = [];
        }

        stdout: SplitParser {
            onRead: line => {
                if (!line)
                    return;
                try {
                    root.handle(JSON.parse(line));
                } catch (e) {}
            }
        }

        stderr: SplitParser {
            onRead: line => {
                if (line.trim())
                    root.error = line.trim();
            }
        }

        onExited: code => {
            const crashed = !root.stopping && code !== 0;
            root.busy = false;
            root.thinking = false;
            root.streamIndex = -1;
            for (const id of Object.keys(root.approvals)) {
                for (let i = root.messages.count - 1; i >= 0; i--)
                    if (root.messages.get(i).callId === id)
                        root.messages.setProperty(i, "phase", "denied");
            }
            root.approvals = {};
            root.pendingApprovals = 0;
            root.activeId = "";
            root.stopping = false;
            root.ready = false;
            idle.stop();
            if (crashed) {
                root.push("error", `Claude exited (${code})${root.error ? `: ${root.error}` : ""}. Send a message to restart.`, "", "", "");
                root.notify("Crashed");
                root.returnQueue();
            }
            if (root.restartQueued) {
                root.restartQueued = false;
                root.start();
            }
        }
    }
}
