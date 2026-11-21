import QtQuick
import Quickshell
import qs.launcher
import qs.palette
import qs.providers
import qs.services

ShellRoot {
    id: root

    property int at: -1
    property int failed: 0

    function check(value: bool, message: string): void {
        if (value)
            return;
        failed++;
        console.log(`FAIL: ${message}`);
    }

    function first(): var {
        return search.results[0] ?? ({});
    }

    readonly property var steps: [
        () => {
            check(launcher.modes.map(m => m.id).join() === "apps,themes,fonts,wallpapers,session", "launcher keeps its five modes");
            launcher.mode = "session";
            check(launcher.results.length === 6, "launcher lists six session actions");
            check(!launcher.activate({
                kind: "blank"
            }), "launcher ignores grid padding");
            launcher.mode = "themes";
            launcher.query = "light";
            check(launcher.results.length === 1 && launcher.results[0].base === "kanagawa", "launcher filters themes by substring");
            view.input.text = "kana";
        },
        () => {
            check(first().title === "Kanagawa" && first().tag === "Theme", `fuzzy search finds the theme first, got ${first().title}`);
            check(search.results[search.results.length - 1].provider === WebProvider, "web search is the last result");
            view.input.text = "do not";
        },
        () => {
            const before = Notifs.dnd;
            check(first().title === "Do not disturb" && first().tag === (before ? "On" : "Off"), "toggle shows its state");
            check(view.actions[0].stay === true, "toggle keeps the palette open");
            view.accept();
            check(Notifs.dnd !== before && first().tag === (before ? "Off" : "On"), "Enter flips the toggle and the row follows");
            Notifs.dnd = before;
            view.input.text = "";
            const zen = search.candidates.find(c => c.key === "commands:Zen mode");
            search.run(zen, search.pinAction(zen));
        },
        () => {
            check(first().key === "commands:Zen mode" && first().tag === "Pinned", "a pinned entry leads the empty list");
            const zen = search.candidates.find(c => c.key === "commands:Zen mode");
            search.run(zen, search.pinAction(zen));
            check(search.pins.length === 0, "unpinning clears the pin");
            view.input.text = ":";
        },
        () => {
            check(search.scope === SymbolProvider, "colon opens the symbol scope");
            check(SymbolProvider.entries.length > 1000, "the symbol list loaded");
            view.input.text = "rocket";
        },
        () => {
            check(first().title === "rocket", `symbol search finds the rocket, got ${first().title}`);
            search.scope = null;
            view.input.text = "/";
        },
        () => {
            check(!FileProvider.enabled || search.scope === FileProvider, "slash opens the file scope");
            search.scope = null;
            view.input.text = "!";
        },
        () => {
            check(search.scope === RunProvider, "bang opens the run scope");
            view.input.text = "printf 'one\\ntwo\\n'; echo three >&2; exit 3";
        },
        () => view.accept(),
        () => {
            check(view.runner === RunProvider, "running a command shows the output pane");
            check(RunProvider.text === "one\ntwo\nthree" && RunProvider.code === 3, `output and exit code are captured, got ${JSON.stringify(RunProvider.text)} ${RunProvider.code}`);
            check(RunProvider.history[0].startsWith("printf"), "the command is remembered");
            view.input.text = "";
        },
        () => {
            check(view.runner === null && first().tag === "History", "editing leaves the output and history is offered");
            search.scope = null;
            view.input.text = "6 * 7";
        },
        () => {
            check(!CalcProvider.enabled || (first().card && first().title === "42"), `calculator answers inline, got ${first().title}`);
            view.input.text = "cpu";
        },
        () => {
            if (Monitor.ready) {
                check(first().title === "CPU" && view.actions[0].label === "Show details", "a system row offers its details");
                view.accept();
                check(search.results[1].indent > 0 && search.results.filter(r => r.indent > 0).length <= 5, "Enter opens a sub-list of at most five");
                view.accept();
                check(search.results.every(r => !r.indent), "Enter again closes it");
            }
            console.log(root.failed ? `FAIL: ${root.failed} palette checks failed` : "PASS: palette search, scopes, toggles, pins, and command output");
            Qt.quit();
        }
    ]

    LauncherModel {
        id: launcher
    }

    PaletteModel {
        id: search
    }

    FloatingWindow {
        visible: true
        implicitWidth: 700
        implicitHeight: 520

        PaletteView {
            id: view

            model: search
            onActivated: (entry, action) => search.run(entry, action)
        }
    }

    Timer {
        id: tick

        interval: 450
        repeat: true
        onTriggered: {
            root.at++;
            if (root.at < root.steps.length)
                root.steps[root.at]();
        }
    }

    Timer {
        interval: 2600
        running: true
        onTriggered: {
            Dotfiles.themes = [
                {
                    name: "kanagawa"
                },
                {
                    name: "kanagawa-light"
                },
                {
                    name: "ayu"
                }
            ];
            tick.start();
        }
    }
}
