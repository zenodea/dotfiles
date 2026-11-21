import QtQuick
import Quickshell
import Quickshell.Io
import qs.providers
import "fuzzy.js" as Fuzzy

Scope {
    id: root

    property string query: ""
    property var usage: ({})
    property var pins: []

    property var scope: null
    property string expanded: ""

    readonly property int limit: scope ? 200 : 50
    readonly property var providers: [CalcProvider, AppProvider, WindowProvider, CommandProvider, ControlProvider, MediaProvider, SystemProvider, ScriptProvider, ThemeProvider, FontProvider, WallpaperProvider, SessionProvider, ClipboardProvider, FileProvider, RunProvider, SymbolProvider, WebProvider].filter(p => p.enabled !== false)
    readonly property var searched: scope ? [scope] : providers.filter(p => !p.scoped)
    readonly property var prefixes: providers.filter(p => p.prefix).map(p => ({
                key: p.prefix,
                label: p.label
            }))

    readonly property var candidates: {
        const found = [].concat(...searched.filter(p => !p.live).map(p => p.results("").filter(i => i.kind !== "blank").map(i => entry(p, i))));
        if (scope)
            return found;
        return found.concat(providers.filter(p => p.scoped).map(p => ({
                    provider: p,
                    opens: p,
                    key: `scope:${p.id}`,
                    title: p.label,
                    sub: p.hint ?? "",
                    tag: p.prefix ? `Type ${p.prefix}` : "Command",
                    words: "",
                    mark: "",
                    indent: 0,
                    meter: -1,
                    tint: "",
                    lit: false,
                    card: false,
                    swatch: null,
                    face: "",
                    image: "",
                    glyph: p.glyph
                })));
    }

    readonly property var answers: [].concat(...searched.filter(p => p.live && !p.last).map(p => p.answers.map(i => entry(p, i))))
    readonly property var trailing: [].concat(...searched.filter(p => p.live && p.last).map(p => p.answers.map(i => entry(p, i))))

    readonly property var results: {
        const q = query.trim();
        const now = Date.now();
        const scored = [];
        for (let index = 0; index < candidates.length; index++) {
            const found = candidates[index];
            let score = 0;
            let positions = [];
            if (q) {
                const title = Fuzzy.match(q, found.title);
                const worded = found.words !== "" && Fuzzy.contains(q, found.words);
                if (!title && !worded && !Fuzzy.contains(q, found.sub))
                    continue;
                const byWords = !worded ? 30 : found.words.split(" ").includes(q.toLowerCase()) ? 120 : 90;
                score = Math.max(title ? title.score : 0, byWords) + (found.provider.weight ?? 0);
                positions = title ? title.positions : [];
            }
            const pinned = !q && !scope ? pins.indexOf(found.key) : -1;
            scored.push({
                found,
                index,
                positions,
                pinned: pinned >= 0,
                score: pinned >= 0 ? 1000 - pinned : score + boost(found.key, now)
            });
        }
        scored.sort((a, b) => b.score - a.score || a.index - b.index);
        const ranked = scored.slice(0, limit).map(s => Object.assign({
                positions: s.positions
            }, s.found, s.pinned ? {
                tag: "Pinned",
                lit: true
            } : {}));
        const parent = expanded ? ranked.findIndex(r => r.key === expanded) : -1;
        if (parent >= 0)
            ranked.splice(parent + 1, 0, ...(ranked[parent].item?.children ?? []).slice(0, 5).map(i => Object.assign({
                    positions: []
                }, entry(ranked[parent].provider, i), {
                    indent: 22
                })));
        return answers.concat(ranked, trailing);
    }

    onQueryChanged: {
        expanded = "";
        ask();
    }
    onScopeChanged: ask()

    function prefixed(first: string): var {
        return first ? providers.find(p => p.scoped && p.prefix === first) ?? null : null;
    }

    function ask(): void {
        for (const p of providers)
            if (p.live)
                p.ask(searched.includes(p) ? query : "");
    }

    function entry(provider: var, item: var): var {
        return {
            provider,
            item,
            key: `${provider.id}:${item.name}`,
            title: item.title ?? item.label ?? item.name,
            sub: item.sub ?? "",
            tag: item.tag ?? provider.tag,
            words: item.keywords ?? "",
            mark: item.mark ?? "",
            indent: 0,
            meter: item.meter ?? -1,
            tint: item.tint ?? "",
            lit: item.on === true,
            card: item.card === true,
            swatch: item.swatch ?? null,
            face: item.face ?? "",
            image: item.image ?? (provider.pictures ? item.icon : ""),
            glyph: provider.pictures ? provider.glyph ?? "" : item.icon ?? provider.glyph
        };
    }

    function boost(key: string, now: real): real {
        const used = usage[key];
        if (!used)
            return 0;
        return Math.min(40, 8 * Math.log2(1 + used.n)) * Math.pow(0.5, (now - used.t) / 2592000000);
    }

    function actions(entry: var): var {
        if (entry.opens)
            return [
                {
                    label: "Open",
                    stay: true,
                    run: () => root.scope = entry.opens
                },
                pinAction(entry)
            ];
        const provider = entry.provider;
        const item = entry.item;
        const found = provider.actions ? provider.actions(item).slice() : [
            {
                label: provider.verb ?? "Open",
                run: () => provider.activate(item)
            }
        ];
        if (item.children?.length) {
            const toggle = {
                label: expanded === entry.key ? "Hide details" : item.more ?? "Show details",
                stay: true,
                unlogged: true,
                run: () => root.expanded = root.expanded === entry.key ? "" : entry.key
            };
            if (item.on === undefined)
                found.unshift(toggle);
            else
                found.push(toggle);
        }
        if (!provider.fleeting && !entry.indent)
            found.push(pinAction(entry));
        return found;
    }

    function pinAction(entry: var): var {
        return {
            label: pins.includes(entry.key) ? "Unpin" : "Pin to top",
            stay: true,
            unlogged: true,
            run: () => {
                root.pins = root.pins.includes(entry.key) ? root.pins.filter(k => k !== entry.key) : root.pins.concat([entry.key]);
                root.save();
            }
        };
    }

    function save(): void {
        store.setText(JSON.stringify({
            usage,
            pins
        }));
    }

    function run(entry: var, action: var): void {
        if (!action.unlogged && !entry.indent && (entry.opens || !entry.provider.fleeting)) {
            const used = usage[entry.key]?.n ?? 0;
            usage = Object.assign({}, usage, {
                [entry.key]: {
                    n: used + 1,
                    t: Date.now()
                }
            });
            save();
        }
        action.run();
    }

    Component.onCompleted: {
        try {
            const saved = JSON.parse(store.text() || "{}");
            const current = Array.isArray(saved.pins) && typeof saved.usage === "object";
            usage = current ? saved.usage : saved;
            pins = current ? saved.pins : [];
        } catch (e) {
            usage = {};
        }
    }

    FileView {
        id: store

        path: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/dotfiles/palette-usage.json`
        blockLoading: true
        printErrors: false
    }
}
