pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int repo: 0
    property int aur: 0
    property int age: -1

    readonly property int total: repo + aur
    readonly property bool known: age >= 0

    readonly property string summary: {
        if (!known)
            return "";
        if (total === 0)
            return "up to date";
        const tail = aur > 0 ? ` (${aur} aur)` : "";
        return `${total} update${total === 1 ? "" : "s"}${tail}`;
    }

    function refresh(): void {
        if (!probe.running)
            probe.running = true;
    }

    Process {
        id: probe

        command: ["bash", `${Quickshell.shellDir}/scripts/updates.sh`]

        stdout: SplitParser {
            onRead: data => {
                if (!data)
                    return;
                const state = JSON.parse(data);
                root.repo = state.repo;
                root.aur = state.aur;
                root.age = state.age;
            }
        }
    }
}
