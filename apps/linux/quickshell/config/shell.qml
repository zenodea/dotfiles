//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import qs.bar
import qs.services

ShellRoot {
    IpcHandler {
        target: "shell"

        function drawer(tab: string): void {
            Panels.toggleDrawer(tab);
        }

        function launcher(mode: string): void {
            Panels.openLauncher(mode);
        }

        function close(): void {
            Panels.close();
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: scope

            required property ShellScreen modelData

            Exclusions {
                screen: scope.modelData
            }

            Frame {
                modelData: scope.modelData
            }
        }
    }
}
