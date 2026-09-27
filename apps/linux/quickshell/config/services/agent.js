.pragma library

// one-line summary of a tool call's input for tool rows and approval cards
function describe(input) {
    if (!input)
        return "";
    const pick = input.command ?? input.file_path ?? input.path ?? input.pattern ?? input.url ?? input.query ?? input.description;
    const text = pick !== undefined ? String(pick) : JSON.stringify(input);
    return text.replace(/\s+/g, " ").slice(0, 400);
}

function entry(role, text, detail, phase, callId) {
    return { role, text, detail: detail ?? "", phase: phase ?? "", callId: callId ?? "" };
}

function hidden(text) {
    return text.startsWith("<") || text.startsWith("[Request interrupted");
}

// rebuilds the panel's entries from a Claude Code transcript (.jsonl)
function replay(text) {
    const out = [];
    const tools = {};
    for (const line of text.split("\n")) {
        let e;
        try {
            e = JSON.parse(line);
        } catch (err) {
            continue;
        }
        if (!e || e.isSidechain || e.isMeta || !e.message)
            continue;
        const content = e.message.content;
        if (e.type === "user") {
            if (typeof content === "string") {
                if (!hidden(content))
                    out.push(entry("user", content));
                continue;
            }
            for (const block of content ?? []) {
                if (block.type === "tool_result" && tools[block.tool_use_id] !== undefined)
                    out[tools[block.tool_use_id]].phase = block.is_error === true ? "error" : "done";
                else if (block.type === "text" && !hidden(block.text))
                    out.push(entry("user", block.text));
            }
        } else if (e.type === "assistant") {
            for (const block of content ?? []) {
                if (block.type === "text" && block.text.trim()) {
                    out.push(entry("assistant", block.text));
                } else if (block.type === "tool_use" && block.name !== "AskUserQuestion") {
                    tools[block.id] = out.length;
                    out.push(entry("tool", block.name, describe(block.input), "done", block.id));
                }
            }
        }
    }
    return out;
}
