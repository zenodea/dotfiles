//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Io
import qs.frame
import qs.services

ShellRoot {
    QtObject {
        Component.onCompleted: {
            Dotfiles.repo;
            ClipboardHistory.available;
            Notifs.count;
        }
    }

    IpcHandler {
        target: "shell"

        function drawer(tab: string): void {
            Panels.toggleDrawer(tab);
        }

        function controls(): void {
            Panels.toggleControls();
        }

        function launcher(mode: string): void {
            Panels.openLauncher(mode);
        }

        function close(): void {
            Panels.close();
        }

        function screenshot(mode: string): void {
            Screenshot.take(mode);
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
