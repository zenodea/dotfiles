import QtQuick
import Quickshell
import Quickshell.Networking
import qs.controls
import qs.services
import qs.style

ShellRoot {
    id: root

    function check(value: bool, message: string): void {
        if (!value)
            throw new Error(message);
    }

    QtObject {
        id: network

        property string name: "Test Wi-Fi"
        property bool connected: false
        property bool known: false
        property bool stateChanging: false
        property real signalStrength: 0.8
        property int security: WifiSecurityType.Wpa2Psk
        property string submitted: ""
        property int connects: 0
        property int disconnects: 0

        signal connectionFailed(int reason)

        function connect(): void { connects++; }
        function disconnect(): void { disconnects++; }
        function connectWithPsk(psk: string): void { submitted = psk; }
    }

    TrayMenu {
        id: trayMenu

        trayItem: null
        anchorWindow: testWindow
        anchorX: 0
    }

    FloatingWindow {
        id: testWindow

        visible: true
        implicitWidth: 380
        implicitHeight: 200

        WifiPicker {
            id: wifi
            width: parent.width
            scanning: false
        }
    }

    Timer {
        interval: 200
        running: true
        onTriggered: {
            try {
                if (Quickshell.env("TEST_ZEN_RESTORE") === "1") {
                    root.check(Panels.hidden, "Zen mode must survive a shell restart");
                    root.check(Panels.windowRounding === Metrics.frameRadius, "restored Zen mode must keep rounded corners");
                    Panels.openLauncher("apps");
                    root.check(Panels.hidden && !Panels.anyOpen, "restarting the shell must not bypass Zen mode");
                    Panels.toggleZen();
                    root.check(!Panels.hidden && Panels.windowRounding === 0, "the explicit Zen toggle must restore normal mode");
                    console.log("PASS: Zen mode persists across shell restarts");
                    Qt.quit();
                    return;
                }
                root.check(!Panels.hidden, "a fresh compositor session must start outside Zen mode");

                // Replace only the test instance's model; never connect to a real network.
                const repeater = wifi.children.find(item => typeof item.itemAt === "function");
                repeater.model = [network];
                const entry = repeater.itemAt(0);
                const editor = entry.children[1];
                const password = editor.children.find(item => item.echoMode !== undefined);
                const button = editor.children.find(item => item.label === "Connect");

                Panels.controlsByHover = true;
                wifi.pick(network);
                root.check(wifi.asking === network.name, "secured networks must ask for a password");
                root.check(password.activeFocus, "password field must receive keyboard focus");
                root.check(!Panels.controlsByHover, "password entry must not close on pointer leave");
                root.check(!button.enabled, "empty passwords must not be submitted");
                entry.submit();
                root.check(wifi.connecting === null, "empty submit must not start a connection");

                password.text = "test password";
                password.accepted();
                root.check(network.submitted === "test password", "Enter must submit the password");
                root.check(password.text === "", "submitted passwords must be cleared from the editor");
                root.check(wifi.asking === "", "submission must close the editor");

                network.connectionFailed(ConnectionFailReason.NoSecrets);
                root.check(wifi.error !== "", "connection errors must be visible");
                root.check(wifi.asking === network.name, "failed passwords must be retryable");
                password.text = "replacement password";
                button.clicked();
                root.check(network.submitted === "replacement password", "Connect must submit the replacement password");
                network.connected = true;
                root.check(wifi.connecting === null && wifi.error === "", "success must clear pending state and errors");
                wifi.pick(network);
                root.check(network.disconnects === 1, "connected networks must disconnect on click");

                network.connected = false;
                network.known = true;
                wifi.pick(network);
                root.check(network.connects === 1, "saved networks must use their saved credentials");
                network.connectionFailed(ConnectionFailReason.WifiAuthTimeout);
                root.check(wifi.asking === network.name, "bad saved credentials must allow a new password");

                network.known = false;
                for (const security of [WifiSecurityType.Open, WifiSecurityType.Owe]) {
                    network.security = security;
                    wifi.pick(network);
                    root.check(wifi.asking === "", "passwordless networks must not prompt");
                    network.connectionFailed(ConnectionFailReason.WifiNetworkLost);
                    root.check(wifi.error !== "" && wifi.asking === "", "open network errors must not ask for passwords");
                }
                root.check(network.connects === 3, "open and OWE networks must connect directly");
                network.stateChanging = true;
                wifi.pick(network);
                root.check(network.connects === 3, "busy networks must ignore repeated clicks");

                Panels.controls = true;
                Popouts.open = true;
                trayMenu.open();
                root.check(trayMenu.visible, "tray menu must open outside Zen mode");
                Panels.toggleZen();
                root.check(Panels.hidden && !Panels.anyOpen && !Popouts.open && !trayMenu.visible, "Zen mode must close every shell panel, popout, and tray menu");
                root.check(Panels.windowRounding === Metrics.frameRadius, "Zen mode must round window corners");

                const openers = [
                    () => Panels.toggleDrawer("dashboard"),
                    () => Panels.toggleDrawer("system"),
                    () => Panels.toggleControls("controls"),
                    () => Panels.toggleControls("clipboard"),
                    () => Panels.toggleControls("agent"),
                    () => Panels.openLauncher("apps"),
                    () => Panels.openLauncher("session"),
                    () => Panels.openLauncher("themes"),
                    () => Panels.hoverOpenControls(),
                    () => Panels.hoverOpenDrawer(),
                    () => Panels.hoverOpenLauncher(),
                    () => Popouts.show(null, null, {}),
                    () => trayMenu.open(),
                    () => Panels.close()
                ];
                for (const open of openers) {
                    open();
                    root.check(Panels.hidden && !Panels.anyOpen && !Popouts.open && !trayMenu.visible, "shortcuts, hover, popouts, and tray menus must not exit Zen mode");
                    root.check(Panels.windowRounding === Metrics.frameRadius, "blocked openers must keep rounded corners");
                }

                Panels.toggleZen();
                root.check(!Panels.hidden && Panels.windowRounding === 0, "only the explicit Zen toggle must restore normal mode");
                Panels.toggleControls("controls");
                root.check(Panels.controls, "controls must work again outside Zen mode");
                Panels.close();
                Panels.toggleDrawer("dashboard");
                root.check(Panels.drawer, "drawer must work again outside Zen mode");
                Panels.close();
                Panels.openLauncher("apps");
                root.check(Panels.launcher === "apps", "launcher must work again outside Zen mode");
                Panels.close();

                // Leave the marker enabled for the second process's persistence check.
                Panels.toggleZen();
                console.log("PASS: Wi-Fi password entry, retries, and sticky Zen mode");
                Qt.quit();
            } catch (error) {
                console.error("FAIL:", error.message);
                Qt.exit(1);
            }
        }
    }
}
