import QtQuick
import qs.providers

// what the launcher lists for each mode, and what activating an entry does
QtObject {
    id: root

    property string mode: "apps"
    property string query: ""

    readonly property var providers: [AppProvider, ThemeProvider, FontProvider, WallpaperProvider, SessionProvider]
    readonly property var modes: providers.map(p => ({
                id: p.id,
                label: p.label
            }))
    readonly property var provider: providers.find(p => p.id === mode) ?? null
    readonly property var results: provider ? provider.results(query).slice(0, provider.cap || undefined) : []

    function nextMode(): string {
        const i = modes.findIndex(m => m.id === mode);
        return modes[(i + 1) % modes.length].id;
    }

    // returns false for entries that do nothing (grid padding)
    function activate(item: var): bool {
        if (!provider || !item || item.kind === "blank")
            return false;
        provider.activate(item);
        return true;
    }
}
