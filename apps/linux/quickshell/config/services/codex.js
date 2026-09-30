.pragma library
.import "agent.js" as AgentJs

function tool(item) {
    switch (item.type) {
    case "commandExecution":
        return { name: "Shell", detail: item.command };
    case "fileChange":
        return { name: "Edit", detail: (item.changes ?? []).map(c => c.path).join(" ") };
    case "mcpToolCall":
        return { name: `${item.server}.${item.tool}`, detail: AgentJs.describe(item.arguments) };
    case "dynamicToolCall":
        return { name: item.tool, detail: AgentJs.describe(item.arguments) };
    case "webSearch":
        return { name: "WebSearch", detail: item.query };
    case "imageView":
        return { name: "View", detail: item.path };
    }
    return null;
}

function failed(item) {
    return item.status === "failed" || item.status === "declined";
}

function replay(turns) {
    const out = [];
    for (const turn of turns) {
        for (const item of turn.items ?? []) {
            if (item.type === "userMessage") {
                const text = (item.content ?? []).filter(c => c.type === "text").map(c => c.text).join("\n");
                if (text.trim())
                    out.push(AgentJs.entry("user", text));
            } else if (item.type === "agentMessage") {
                if (item.text.trim())
                    out.push(AgentJs.entry("assistant", item.text));
            } else {
                const t = tool(item);
                if (t)
                    out.push(AgentJs.entry("tool", t.name, t.detail, failed(item) ? "error" : "done", item.id));
            }
        }
    }
    return out;
}

function permissions(params) {
    const wanted = params.permissions ?? {};
    const parts = [];
    if (wanted.network?.enabled)
        parts.push("network access");
    for (const path of wanted.fileSystem?.write ?? [])
        parts.push(`write ${path}`);
    for (const path of wanted.fileSystem?.read ?? [])
        parts.push(`read ${path}`);
    for (const entry of wanted.fileSystem?.entries ?? [])
        parts.push(`${entry.access} ${entry.path.path ?? entry.path.pattern ?? entry.path.value?.kind ?? ""}`);
    if (params.reason)
        parts.push(params.reason);
    return parts.join(" · ");
}

function choices(field) {
    if (field.type === "boolean")
        return [{ label: "Yes", value: true }, { label: "No", value: false }];
    const items = field.type === "array" ? field.items ?? {} : field;
    const titled = items.oneOf ?? items.anyOf;
    if (titled)
        return titled.map(option => ({ label: option.title, value: option.const }));
    return (items.enum ?? []).map((value, i) => ({ label: field.enumNames?.[i] ?? value, value }));
}

function form(params) {
    return Object.entries(params.requestedSchema?.properties ?? {}).map(([key, field], i) => {
        const title = field.title ?? key;
        const text = field.description ? `${title}: ${field.description}` : title;
        const picks = choices(field);
        return {
            key,
            kind: field.type,
            picks,
            header: params.serverName,
            question: i === 0 ? `${params.message}\n\n${text}` : text,
            multiSelect: field.type === "array",
            options: picks.map(pick => ({ label: pick.label, description: "" }))
        };
    });
}

function formContent(fields, answers) {
    const out = {};
    for (const field of fields) {
        const raw = answers[field.question] ?? "";
        if (raw === "")
            continue;
        const value = label => {
            const pick = field.picks.find(p => p.label === label);
            return pick ? pick.value : label;
        };
        if (field.kind === "array")
            out[field.key] = raw.split(", ").map(value);
        else if (field.kind === "number" || field.kind === "integer")
            out[field.key] = Number(raw);
        else
            out[field.key] = value(raw);
    }
    return out;
}
