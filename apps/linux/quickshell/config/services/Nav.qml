pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    property var items: []
    property Item current: null
    property bool active: false
    property Item keys: null
    property Item searchField: null

    readonly property var drawerTabs: ["dashboard", "windows", "clipboard"]
    readonly property var controlsTabs: ["controls", "agent"]

    function register(item: Item): void {
        items.push(item);
    }

    function unregister(item: Item): void {
        const at = items.indexOf(item);
        if (at >= 0)
            items.splice(at, 1);
        if (current === item)
            current = null;
    }

    function reset(): void {
        current = null;
        active = false;
    }

    function refocus(): void {
        if (keys)
            keys.forceActiveFocus();
    }

    function secondary(name: string): bool {
        if (!current || typeof current[name] !== "function")
            return false;
        current[name]();
        return true;
    }

    function inScope(item: Item): bool {
        for (let node = item; node; node = node.parent) {
            if (node.navScope === true)
                return true;
            if (node.navScope === false)
                return false;
        }
        return false;
    }

    function ordered(): var {
        const rows = [];
        for (const item of items) {
            if (!item.visible || item.width <= 0 || item.height <= 0 || !inScope(item))
                continue;
            if (item.navigable === false || item.enabled === false)
                continue;
            const pos = item.mapToItem(null, 0, 0);
            rows.push({
                item: item,
                x: pos.x,
                y: pos.y,
                h: item.height
            });
        }
        rows.sort((a, b) => Math.abs(a.y - b.y) < Math.min(a.h, b.h) / 2 ? a.x - b.x : a.y - b.y);
        return rows;
    }

    function wake(): bool {
        if (active && current && current.visible)
            return true;
        active = true;
        const rows = ordered();
        current = rows.length > 0 ? rows[0].item : null;
        reveal();
        return false;
    }

    function lines(rows: var): var {
        const out = [];
        for (const row of rows) {
            const line = out[out.length - 1];
            if (line && Math.abs(row.y - line[0].y) < Math.min(row.h, line[0].h) / 2)
                line.push(row);
            else
                out.push([row]);
        }
        return out;
    }

    function move(delta: int): void {
        if (!wake())
            return;
        const grid = lines(ordered());
        const at = grid.findIndex(line => line.some(r => r.item === current));
        if (at < 0) {
            if (grid.length > 0)
                current = grid[0][0].item;
            reveal();
            return;
        }
        const target = grid[Math.max(0, Math.min(grid.length - 1, at + delta))];
        const here = grid[at].find(r => r.item === current);
        const centre = here.x + here.item.width / 2;
        let best = target[0];
        for (const row of target) {
            if (Math.abs(row.x + row.item.width / 2 - centre) < Math.abs(best.x + best.item.width / 2 - centre))
                best = row;
        }
        current = best.item;
        reveal();
    }

    function sideways(delta: int): bool {
        if (!wake())
            return true;
        const rows = ordered();
        const at = rows.findIndex(r => r.item === current);
        if (at < 0)
            return false;
        const to = at + delta;
        if (to < 0 || to >= rows.length)
            return false;
        if (Math.abs(rows[to].y - rows[at].y) >= Math.min(rows[to].h, rows[at].h) / 2)
            return false;
        current = rows[to].item;
        reveal();
        return true;
    }

    function edge(last: bool): void {
        active = true;
        const rows = ordered();
        if (rows.length > 0)
            current = rows[last ? rows.length - 1 : 0].item;
        reveal();
    }

    function page(delta: int): void {
        const flick = flickableOf(current);
        if (flick)
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + delta * flick.height / 2));
        move(delta * 4);
    }

    function activate(): void {
        if (!wake())
            return;
        if (current && typeof current.activate === "function")
            current.activate();
    }

    function adjust(delta: int): bool {
        if (!current || typeof current.adjust !== "function")
            return false;
        current.adjust(delta);
        return true;
    }

    function cycleTab(delta: int): void {
        const panels = Panels;
        if (panels.drawer) {
            const at = drawerTabs.indexOf(panels.drawerTab);
            panels.drawerTab = drawerTabs[(at + delta + drawerTabs.length) % drawerTabs.length];
        } else if (panels.controls) {
            const at = controlsTabs.indexOf(panels.controlsTab);
            panels.controlsTab = controlsTabs[(at + delta + controlsTabs.length) % controlsTabs.length];
        }
        current = null;
    }

    function flickableOf(item: Item): var {
        for (let node = item; node; node = node.parent) {
            if (node.contentY !== undefined && node.contentHeight !== undefined && node.flicking !== undefined)
                return node;
        }
        return null;
    }

    function reveal(): void {
        const flick = flickableOf(current);
        if (!flick || !current)
            return;
        const top = current.mapToItem(flick.contentItem, 0, 0).y;
        const bottom = top + current.height;
        const margin = 24;
        if (top - margin < flick.contentY)
            flick.contentY = Math.max(0, top - margin);
        else if (bottom + margin > flick.contentY + flick.height)
            flick.contentY = Math.min(flick.contentHeight - flick.height, bottom + margin - flick.height);
    }

    function handle(event: var): bool {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const shift = event.modifiers & Qt.ShiftModifier;
        switch (event.key) {
        case Qt.Key_J:
            move(1);
            return true;
        case Qt.Key_K:
            move(-1);
            return true;
        case Qt.Key_Down:
            move(1);
            return true;
        case Qt.Key_Up:
            move(-1);
            return true;
        case Qt.Key_H:
            if (shift)
                cycleTab(-1);
            else if (!adjust(-1))
                sideways(-1);
            return true;
        case Qt.Key_L:
            if (shift)
                cycleTab(1);
            else if (!adjust(1))
                sideways(1);
            return true;
        case Qt.Key_Left:
            if (!adjust(-1))
                sideways(-1);
            return true;
        case Qt.Key_Right:
            if (!adjust(1))
                sideways(1);
            return true;
        case Qt.Key_Tab:
            cycleTab(1);
            return true;
        case Qt.Key_Backtab:
            cycleTab(-1);
            return true;
        case Qt.Key_G:
            edge(shift);
            return true;
        case Qt.Key_D:
            if (ctrl) {
                page(1);
                return true;
            }
            return false;
        case Qt.Key_U:
            if (ctrl) {
                page(-1);
                return true;
            }
            return false;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            activate();
            return true;
        case Qt.Key_X:
            return secondary("dismiss");
        case Qt.Key_M:
            return secondary("menu");
        case Qt.Key_Slash:
            if (!searchField || !searchField.visible)
                return false;
            searchField.forceActiveFocus();
            return true;
        }
        return false;
    }
}
