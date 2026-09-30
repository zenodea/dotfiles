import QtQuick
import Quickshell
import qs.services
import "codex.js" as CodexJs

AgentBackend {
    id: root

    property string threadId: ""
    property string turnId: ""
    property var details: ({})
    property var pending: []

    binary: "codex"
    label: "Codex"
    installHint: "npm install -g @openai/codex"
    models: ["default"].concat(AgentInfo.codexCatalog.map(entry => entry.model))
    efforts: ["default"].concat(AgentInfo.codexCatalog.find(entry => host.model === "default" ? entry.preferred : entry.model === host.model)?.efforts ?? [])
    modes: [
        {
            id: "read-only",
            hint: "reads freely, asks before anything else",
            approvalPolicy: "on-request",
            sandbox: "read-only"
        },
        {
            id: "ask",
            hint: "asks before any command it doesn't know is safe",
            approvalPolicy: "untrusted",
            sandbox: "workspace-write"
        },
        {
            id: "auto",
            hint: "works freely in its scratch folder, asks to go outside it",
            approvalPolicy: "on-request",
            sandbox: "workspace-write"
        }
    ]

    function args(): var {
        return ["app-server"];
    }

    function restore(sessionId: string): void {
        host.start();
    }

    function erase(sessionId: string): void {
        Quickshell.execDetached(["sh", "-c", host.pathPrefix + 'exec codex delete --force "$0"', sessionId]);
    }

    function call(method: string, params: var, done: var): void {
        const id = ++seq;
        if (done)
            waiting[id] = done;
        write({
            id,
            method,
            params
        });
    }

    function send(text: string, files: var): void {
        if (threadId === "") {
            pending = pending.concat([
                {
                    text,
                    files
                }
            ]);
            return;
        }
        const params = {
            threadId,
            input: files.map(f => ({
                        type: "localImage",
                        path: f.path
                    })).concat([
                {
                    type: "text",
                    text
                }
            ])
        };
        if (setup.effort !== "default")
            params.effort = setup.effort;
        call("turn/start", params, (result, error) => {
            if (error)
                root.host.turnEnded(true, String(error.message));
            else
                root.turnId = result.turn.id;
        });
    }

    function interrupt(): void {
        if (threadId !== "" && turnId !== "")
            call("turn/interrupt", {
                threadId,
                turnId
            }, null);
    }

    function ruling(request: var, verdict: string): var {
        const p = request.params ?? {};
        const allow = verdict !== "deny";
        switch (request.method) {
        case "item/tool/requestUserInput":
            return {
                answers: {}
            };
        case "mcpServer/elicitation/request":
            if (!allow || request.fields.length > 0)
                return {
                    action: "decline"
                };
            return p.mode === "url" ? {
                action: "accept"
            } : {
                action: "accept",
                content: {}
            };
        case "item/permissions/requestApproval":
            return {
                permissions: allow ? p.permissions : {},
                scope: verdict === "always" ? "session" : "turn"
            };
        case "item/commandExecution/requestApproval":
            if (verdict === "always" && p.proposedExecpolicyAmendment?.length > 0)
                return {
                    decision: {
                        acceptWithExecpolicyAmendment: {
                            execpolicy_amendment: p.proposedExecpolicyAmendment
                        }
                    }
                };
        }
        return {
            decision: verdict === "always" ? "acceptForSession" : allow ? "accept" : "decline"
        };
    }

    function decide(requestId: string, verdict: string): void {
        const request = take(requestId);
        if (!request)
            return;
        if (verdict !== "deny" && request.params?.mode === "url")
            Qt.openUrlExternally(request.params.url);
        write({
            id: request.id,
            result: ruling(request, verdict)
        });
    }

    function answer(requestId: string, answers: var): void {
        const request = take(requestId);
        if (!request)
            return;
        if (request.method === "mcpServer/elicitation/request") {
            write({
                id: request.id,
                result: {
                    action: "accept",
                    content: CodexJs.formContent(request.fields, answers)
                }
            });
            return;
        }
        const out = {};
        for (const q of request.params.questions)
            out[q.id] = {
                answers: [answers[q.question] ?? ""]
            };
        write({
            id: request.id,
            result: {
                answers: out
            }
        });
    }

    function attach(result: var, error: var): void {
        if (error) {
            host.turnEnded(true, String(error.message));
            return;
        }
        threadId = result.thread.id;
        host.sessionStarted(threadId);
        if (host.messages.count === 0)
            for (const e of CodexJs.replay(result.thread.turns ?? []))
                host.messages.append(e);
        const queued = pending;
        pending = [];
        for (const message of queued)
            send(message.text, message.files);
        if (!host.busy)
            host.rest();
    }

    function ask(message: var): void {
        const p = message.params ?? {};
        const key = `codex-${message.id}`;
        let card;
        switch (message.method) {
        case "item/commandExecution/requestApproval":
            card = ["approval", "Shell", p.command ?? details[p.itemId] ?? p.reason ?? "", true];
            break;
        case "item/fileChange/requestApproval":
            card = ["approval", "Edit", details[p.itemId] ?? p.reason ?? "", true];
            break;
        case "item/permissions/requestApproval":
            card = ["approval", "Permissions", CodexJs.permissions(p), true];
            break;
        case "item/tool/requestUserInput":
            card = ["question", "", JSON.stringify(p.questions ?? []), false];
            break;
        case "mcpServer/elicitation/request":
            message.fields = CodexJs.form(p);
            if (message.fields.length > 0)
                card = ["question", "", JSON.stringify(message.fields), false];
            else
                card = ["approval", p.serverName, p.mode === "url" ? `${p.message}\n${p.url}` : p.message, false];
            break;
        default:
            write({
                id: message.id,
                error: {
                    code: -32601,
                    message: "Not supported by this client."
                }
            });
            return;
        }
        requests[key] = message;
        host.request(key, card[0], card[1], card[2], card[3]);
    }

    function itemStarted(item: var): void {
        if (item.type === "agentMessage") {
            host.thinking = false;
            host.beginText();
        } else if (item.type === "reasoning") {
            host.thinking = true;
        } else {
            const tool = CodexJs.tool(item);
            if (!tool)
                return;
            details[item.id] = tool.detail;
            host.addTool(item.id, tool.name, tool.detail);
        }
    }

    function itemCompleted(item: var): void {
        if (item.type === "agentMessage")
            host.endText(item.text ?? "");
        else if (item.type === "reasoning")
            host.thinking = false;
        else
            host.markTool(item.id, CodexJs.failed(item));
    }

    function handle(message: var): void {
        if (message.method === undefined) {
            const done = waiting[message.id];
            delete waiting[message.id];
            if (done)
                done(message.result, message.error);
            return;
        }
        if (message.id !== undefined) {
            ask(message);
            return;
        }
        const p = message.params ?? {};
        if (p.threadId !== threadId)
            return;
        switch (message.method) {
        case "turn/started":
            turnId = p.turn.id;
            break;
        case "item/started":
            itemStarted(p.item);
            break;
        case "item/agentMessage/delta":
            host.appendText(p.delta);
            break;
        case "item/completed":
            itemCompleted(p.item);
            break;
        case "serverRequest/resolved":
            take(`codex-${p.requestId}`);
            host.dropRequest(`codex-${p.requestId}`);
            break;
        case "thread/tokenUsage/updated":
            host.setContext(p.tokenUsage.last.totalTokens, p.tokenUsage.modelContextWindow ?? 0);
            host.spend = `used ${host.count(p.tokenUsage.total.totalTokens)} tokens`;
            break;
        case "turn/completed":
            turnId = "";
            host.turnEnded(p.turn.status === "failed", String(p.turn.error?.message ?? "Request failed"));
            break;
        }
    }

    onOpened: {
        call("initialize", {
            clientInfo: {
                name: "quickshell",
                title: "Quickshell",
                version: "1"
            }
        }, null);
        write({
            method: "initialized"
        });
        const mode = modes.find(m => m.id === setup.mode);
        const params = {
            cwd: host.workDir,
            developerInstructions: host.systemPrompt,
            approvalPolicy: mode.approvalPolicy,
            sandbox: mode.sandbox
        };
        if (setup.model !== "default")
            params.model = setup.model;
        if (setup.sessionId)
            params.threadId = setup.sessionId;
        call(setup.sessionId ? "thread/resume" : "thread/start", params, root.attach);
    }

    onHalted: {
        threadId = "";
        turnId = "";
        details = {};
        pending = [];
    }
}
