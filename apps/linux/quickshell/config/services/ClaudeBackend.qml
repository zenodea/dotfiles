import QtQuick
import Quickshell
import Quickshell.Io
import "agent.js" as AgentJs

AgentBackend {
    id: root

    readonly property string transcriptDir: `${Quickshell.env("HOME")}/.claude/projects/${host.workDir.replace(/[^A-Za-z0-9]/g, "-")}`

    binary: "claude"
    label: "Claude"
    installHint: "curl -fsSL https://claude.ai/install.sh | bash"
    models: ["default", "haiku", "sonnet", "opus"]
    efforts: ["default", "low", "medium", "high", "xhigh", "max"]
    modes: [
        {
            id: "ask",
            hint: "asks before edits and commands"
        },
        {
            id: "edits",
            hint: "edits files without asking, still asks before commands",
            flag: "acceptEdits"
        },
        {
            id: "auto",
            hint: "Claude judges what is safe and only asks when unsure",
            flag: "auto"
        }
    ]

    function args(): var {
        const out = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--permission-prompt-tool", "stdio", "--disallowedTools", "EnterPlanMode,ExitPlanMode,EnterWorktree,ExitWorktree", "--append-system-prompt", host.systemPrompt];
        const flag = modes.find(m => m.id === setup.mode)?.flag;
        if (setup.model !== "default")
            out.push("--model", setup.model);
        if (setup.effort !== "default")
            out.push("--effort", setup.effort);
        if (flag)
            out.push("--permission-mode", flag);
        if (setup.sessionId)
            out.push("--resume", setup.sessionId);
        return out;
    }

    function query(subtype: string, done: var): void {
        const id = `qs-${++seq}`;
        if (done)
            waiting[id] = done;
        write({
            type: "control_request",
            request_id: id,
            request: {
                subtype
            }
        });
    }

    function measure(): void {
        query("get_context_usage", usage => root.host.setContext(usage.totalTokens ?? -1, usage.maxTokens ?? 0));
    }

    function restore(sessionId: string): void {
        transcript.path = "";
        transcript.path = `${transcriptDir}/${sessionId}.jsonl`;
    }

    function erase(sessionId: string): void {
        if (/^[0-9a-f-]{36}$/.test(sessionId))
            Quickshell.execDetached(["rm", "-rf", "--", `${transcriptDir}/${sessionId}`, `${transcriptDir}/${sessionId}.jsonl`]);
    }

    function send(text: string, files: var): void {
        const images = files.map(f => ({
                    type: "image",
                    source: {
                        type: "base64",
                        media_type: f.media,
                        data: f.data
                    }
                }));
        write({
            type: "user",
            message: {
                role: "user",
                content: images.length > 0 ? images.concat([
                    {
                        type: "text",
                        text
                    }
                ]) : text
            }
        });
    }

    function interrupt(): void {
        query("interrupt", null);
    }

    function respond(requestId: string, response: var): void {
        write({
            type: "control_response",
            response: {
                subtype: "success",
                request_id: requestId,
                response
            }
        });
    }

    function decide(requestId: string, verdict: string): void {
        const request = take(requestId);
        if (!request)
            return;
        if (verdict === "deny") {
            respond(requestId, {
                behavior: "deny",
                message: "The user denied this from the panel."
            });
            return;
        }
        const response = {
            behavior: "allow",
            updatedInput: request.input
        };
        if (verdict === "always")
            response.updatedPermissions = request.offer;
        respond(requestId, response);
    }

    function answer(requestId: string, answers: var): void {
        const request = take(requestId);
        if (request)
            respond(requestId, {
                behavior: "allow",
                updatedInput: Object.assign({}, request.input, {
                    answers
                })
            });
    }

    function ask(requestId: string, req: var): void {
        if (req.tool_name === "AskUserQuestion") {
            requests[requestId] = {
                input: req.input
            };
            host.request(requestId, "question", "", JSON.stringify(req.input?.questions ?? []), false);
            return;
        }
        const suggested = req.permission_suggestions ?? [];
        const rules = suggested.filter(s => s.type === "addRules");
        requests[requestId] = {
            input: req.input,
            offer: rules.length > 0 ? rules : suggested
        };
        host.request(requestId, "approval", req.display_name ?? req.tool_name, AgentJs.describe(req.input), suggested.length > 0);
    }

    function handleSubagent(event: var): void {
        if (event.type !== "assistant")
            return;
        for (const block of event.message?.content ?? [])
            if (block.type === "tool_use")
                host.setToolDetail(event.parent_tool_use_id, `↳ ${block.name} ${AgentJs.describe(block.input)}`);
    }

    function handle(event: var): void {
        if (event.parent_tool_use_id) {
            handleSubagent(event);
            return;
        }
        switch (event.type) {
        case "system":
            if (event.subtype === "init")
                host.sessionStarted(event.session_id ?? "");
            if (event.permissionMode !== undefined)
                note = setup.mode === "auto" && event.permissionMode !== "auto" ? "auto isn't available with this model, so it asks instead" : "";
            break;
        case "control_response":
            {
                const response = event.response ?? {};
                const done = waiting[response.request_id];
                delete waiting[response.request_id];
                if (done && response.subtype === "success")
                    done(response.response ?? {});
                break;
            }
        case "stream_event":
            {
                const e = event.event ?? {};
                if (e.type === "content_block_start") {
                    const kind = e.content_block?.type;
                    host.thinking = kind === "thinking";
                    if (kind === "text")
                        host.beginText();
                } else if (e.type === "content_block_delta" && e.delta?.type === "text_delta") {
                    host.appendText(e.delta.text);
                }
                break;
            }
        case "assistant":
            host.endText("");
            for (const block of event.message?.content ?? [])
                if (block.type === "tool_use" && block.name !== "AskUserQuestion")
                    host.addTool(block.id, block.name, AgentJs.describe(block.input));
            break;
        case "user":
            for (const block of event.message?.content ?? [])
                if (block.type === "tool_result")
                    host.markTool(block.tool_use_id, block.is_error === true);
            break;
        case "control_request":
            if (event.request?.subtype === "can_use_tool")
                ask(event.request_id, event.request);
            break;
        case "result":
            if (event.total_cost_usd !== undefined)
                host.spend = `cost $${event.total_cost_usd.toFixed(2)}`;
            measure();
            host.turnEnded(event.is_error === true, String(event.result ?? event.subtype ?? "Request failed"));
            break;
        }
    }

    onOpened: measure()

    FileView {
        id: transcript

        onLoaded: {
            if (root.host.messages.count === 0)
                for (const e of AgentJs.replay(text()))
                    root.host.messages.append(e);
        }
    }
}
