import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    required property var host
    required property string binary
    required property string label
    required property string installHint
    required property var models
    required property var efforts
    required property var modes

    property var setup: ({})
    property string note: ""
    property string path: ""
    property string error: ""
    property bool stopping: false
    property bool ready: false
    property int seq: 0
    property var outbox: []
    property var waiting: ({})
    property var requests: ({})
    property var doomed: []

    readonly property bool available: path !== ""
    readonly property bool running: proc.running

    signal opened
    signal halted

    function start(next: var): void {
        setup = next;
        error = "";
        stopping = false;
        proc.command = ["sh", "-c", host.pathPrefix + 'mkdir -p "$0" && cd "$0" && exec "$@"', host.workDir, path].concat(args());
        proc.running = true;
    }

    function stop(): void {
        if (!proc.running)
            return;
        stopping = true;
        halt();
        proc.running = false;
    }

    function halt(): void {
        ready = false;
        outbox = [];
        waiting = {};
        requests = {};
        note = "";
        halted();
    }

    function forget(sessionId: string): void {
        if (stopping)
            doomed = doomed.concat([sessionId]);
        else
            erase(sessionId);
    }

    function take(requestId: string): var {
        const request = requests[requestId];
        delete requests[requestId];
        return request;
    }

    function write(payload: var): void {
        const line = JSON.stringify(payload) + "\n";
        if (ready)
            proc.write(line);
        else
            outbox = outbox.concat([line]);
    }

    Process {
        running: true
        command: ["sh", "-c", root.host.pathPrefix + `command -v ${root.binary}`]

        stdout: StdioCollector {
            onStreamFinished: root.path = text.trim()
        }
    }

    Process {
        id: proc

        stdinEnabled: true

        onStarted: {
            root.ready = true;
            root.opened();
            for (const line of root.outbox)
                proc.write(line);
            root.outbox = [];
        }

        stdout: SplitParser {
            onRead: line => {
                if (!line)
                    return;
                try {
                    root.handle(JSON.parse(line));
                } catch (e) {}
            }
        }

        stderr: SplitParser {
            onRead: line => {
                if (line.trim())
                    root.error = line.trim();
            }
        }

        onExited: code => {
            const crashed = !root.stopping && code !== 0;
            if (!root.stopping)
                root.halt();
            root.stopping = false;
            for (const id of root.doomed)
                root.erase(id);
            root.doomed = [];
            root.host.exited(root, code, crashed);
        }
    }
}
