//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.frame
import qs.lock
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
            Panels.toggleControls("controls");
        }

        function agent(): void {
            Panels.toggleControls("agent");
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

        function lock(): void {
            Lock.lock();
        }

        function nav(key: string): string {
            const handled = Nav.handle({
                key: Qt["Key_" + key],
                modifiers: 0
            });
            const c = Nav.current;
            return handled ? (c ? `${c.label || c.icon || c.toString()}` : "none") : "unhandled";
        }
    }

    WlSessionLock {
        locked: Lock.locked

        LockSurface {}
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
