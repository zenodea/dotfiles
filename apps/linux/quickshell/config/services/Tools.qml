pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var present: ({})

    function has(name: string): bool {
        return present[name] === true;
    }

    Process {
        running: true
        command: ["sh", "-c", "for t in wl-copy wf-recorder swappy grim slurp brightnessctl hypridle; do command -v $t > /dev/null && echo $t; done"]

        stdout: StdioCollector {
            onStreamFinished: {
                const found = {};
                for (const line of text.trim().split("\n"))
                    if (line)
                        found[line] = true;
                root.present = found;
            }
        }
    }
}
