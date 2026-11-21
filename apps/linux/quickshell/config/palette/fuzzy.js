.pragma library

function boundary(text, i) {
    return i === 0 || " -_./:".includes(text[i - 1]);
}

function subsequence(q, lower, eager) {
    const positions = [];
    let from = 0;
    for (const c of q) {
        let at = lower.indexOf(c, from);
        if (at < 0)
            return null;
        if (eager)
            for (let j = at; j >= 0; j = lower.indexOf(c, j + 1))
                if (boundary(lower, j)) {
                    at = j;
                    break;
                }
        positions.push(at);
        from = at + 1;
    }
    return positions;
}

function token(q, lower) {
    let at = lower.indexOf(q);
    if (at >= 0) {
        for (let j = at; j >= 0; j = lower.indexOf(q, j + 1))
            if (boundary(lower, j)) {
                at = j;
                break;
            }
        const positions = [];
        for (let k = 0; k < q.length; k++)
            positions.push(at + k);
        return {
            score: 100 + (at === 0 ? 40 : boundary(lower, at) ? 25 : 0) - Math.min(40, lower.length - q.length) * 0.5,
            positions
        };
    }
    const positions = subsequence(q, lower, true) ?? subsequence(q, lower, false);
    if (!positions)
        return null;
    let score = 40;
    for (let k = 0; k < positions.length; k++) {
        if (boundary(lower, positions[k]))
            score += 10;
        if (k > 0)
            score += positions[k] === positions[k - 1] + 1 ? 6 : -Math.min(6, positions[k] - positions[k - 1] - 1);
    }
    return score < 40 ? null : {
        score,
        positions
    };
}

function contains(query, text) {
    const lower = text.toLowerCase();
    return query.toLowerCase().split(/\s+/).filter(Boolean).every(q => lower.includes(q));
}

function match(query, text) {
    const lower = text.toLowerCase();
    const seen = new Set();
    let score = 0;
    for (const q of query.toLowerCase().split(/\s+/).filter(Boolean)) {
        const found = token(q, lower);
        if (!found)
            return null;
        score += found.score;
        for (const p of found.positions)
            seen.add(p);
    }
    return {
        score,
        positions: [...seen].sort((a, b) => a - b)
    };
}

function safe(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function marked(text, positions, colour) {
    if (!positions || !positions.length)
        return safe(text);
    const hit = new Set(positions);
    let out = "";
    for (let i = 0; i < text.length; ) {
        let j = i;
        while (j < text.length && hit.has(j) === hit.has(i))
            j++;
        const run = safe(text.slice(i, j));
        out += hit.has(i) ? `<font color="${colour}"><b>${run}</b></font>` : run;
        i = j;
    }
    return out;
}
