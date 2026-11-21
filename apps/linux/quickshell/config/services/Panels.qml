pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.style

Singleton {
    id: root

    property var screen: null
    readonly property bool hidden: zenState.text().trim() === "on"
    property bool drawer: false
    property string drawerTab: "dashboard"
    property string launcher: ""
    property bool palette: false
    property bool controls: false
    property string controlsTab: "controls"

    property bool drawerByHover: false
    property bool launcherByHover: false
    property bool controlsByHover: false

    property bool drawerPointer: false
    property bool drawerEdgePointer: false
    property bool launcherPointer: false
    property bool launcherEdgePointer: false
    property bool controlsPointer: false
    property bool controlsEdgePointer: false

    property bool drawerHoverBlocked: false
    property bool launcherHoverBlocked: false
    property bool controlsHoverBlocked: false

    onWindowRoundingChanged: applyWindowRounding()

    Component.onCompleted: applyWindowRounding()

    onDrawerPointerChanged: judgeDrawer()
    onLauncherPointerChanged: judgeLauncher()
    onControlsPointerChanged: judgeControls()

    onDrawerEdgePointerChanged: {
        if (!drawerEdgePointer)
            drawerHoverBlocked = false;
        judgeDrawer();
    }

    onLauncherEdgePointerChanged: {
        if (!launcherEdgePointer)
            launcherHoverBlocked = false;
        judgeLauncher();
    }

    onControlsEdgePointerChanged: {
        if (!controlsEdgePointer)
            controlsHoverBlocked = false;
        judgeControls();
    }

    readonly property bool anyOpen: drawer || controls || launcher !== ""
    readonly property int windowRounding: hidden ? Metrics.frameRadius : 0

    function applyWindowRounding(): void {
        Hyprland.dispatch(`function() hl.config({ decoration = { rounding = ${windowRounding} } }) end`);
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: var): void {
            if (event.name === "configreloaded")
                root.applyWindowRounding();
        }
    }

    function focusedScreen(): var {
        const monitor = Hyprland.focusedMonitor;
        return Quickshell.screens.find(s => Hyprland.monitorFor(s) === monitor) ?? Quickshell.screens[0] ?? null;
    }

    // Keep Zen mode across shell reloads, but not across compositor sessions.
    FileView {
        id: zenState

        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/dotfiles-zen-${Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")}`
        blockLoading: true
        blockWrites: true
        printErrors: false
        onSaveFailed: error => console.warn("Could not save Zen mode:", error)
    }

    function toggleZen(): void {
        zenState.setText(hidden ? "off" : "on");
        close();
        Popouts.open = false;
        Popouts.source = null;
    }

    function toggleDrawer(tab: string): void {
        if (hidden)
            return;
        Nav.reset();
        const wanted = tab || "dashboard";
        if (drawer && drawerTab === wanted) {
            drawer = false;
            return;
        }
        drawerClose.stop();
        screen = focusedScreen();
        drawerTab = wanted;
        drawerByHover = false;
        launcher = "";
        controls = false;
        palette = false;
        drawer = true;
    }

    function toggleControls(tab: string): void {
        if (hidden)
            return;
        Nav.reset();
        const wanted = tab || "controls";
        if (controls && controlsTab === wanted) {
            controls = false;
            return;
        }
        controlsClose.stop();
        screen = focusedScreen();
        controlsTab = wanted;
        controlsByHover = false;
        launcher = "";
        drawer = false;
        palette = false;
        controls = true;
    }

    function openLauncher(mode: string): void {
        if (hidden)
            return;
        launcherClose.stop();
        screen = focusedScreen();
        drawer = false;
        controls = false;
        palette = false;
        launcherByHover = false;
        launcher = mode || "apps";
    }

    function togglePalette(): void {
        const wanted = !palette;
        close();
        Popouts.open = false;
        Popouts.source = null;
        if (!wanted)
            return;
        screen = focusedScreen();
        palette = true;
    }

    function judgeDrawer(): void {
        if (drawerPointer || drawerEdgePointer)
            drawerClose.stop();
        else if (drawer && drawerByHover)
            drawerClose.restart();
    }

    function judgeLauncher(): void {
        if (launcherPointer || launcherEdgePointer)
            launcherClose.stop();
        else if (launcher !== "" && launcherByHover)
            launcherClose.restart();
    }

    function judgeControls(): void {
        if (controlsPointer || controlsEdgePointer)
            controlsClose.stop();
        else if (controls && controlsByHover)
            controlsClose.restart();
    }

    function hoverOpenDrawer(): void {
        drawerClose.stop();
        if (hidden || anyOpen || drawerHoverBlocked)
            return;
        screen = focusedScreen();
        drawerByHover = true;
        launcher = "";
        drawer = true;
    }

    function hoverOpenLauncher(): void {
        launcherClose.stop();
        if (hidden || anyOpen || launcherHoverBlocked)
            return;
        screen = focusedScreen();
        launcherByHover = true;
        drawer = false;
        launcher = "themes";
    }

    function hoverOpenControls(): void {
        controlsClose.stop();
        if (hidden || anyOpen || controlsHoverBlocked)
            return;
        screen = focusedScreen();
        controlsByHover = true;
        controls = true;
    }

    function close(): void {
        Nav.reset();
        drawerClose.stop();
        launcherClose.stop();
        controlsClose.stop();
        drawerHoverBlocked = drawerPointer || drawerEdgePointer;
        launcherHoverBlocked = launcherPointer || launcherEdgePointer;
        controlsHoverBlocked = controlsPointer || controlsEdgePointer;
        controls = false;
        controlsByHover = false;
        drawer = false;
        drawerByHover = false;
        launcher = "";
        launcherByHover = false;
        palette = false;
    }

    Timer {
        id: drawerClose

        interval: 350
        onTriggered: {
            root.drawer = false;
            root.drawerByHover = false;
        }
    }

    Timer {
        id: controlsClose

        interval: 350
        onTriggered: {
            root.controls = false;
            root.controlsByHover = false;
        }
    }

    Timer {
        id: launcherClose

        interval: 350
        onTriggered: {
            root.launcher = "";
            root.launcherByHover = false;
        }
    }
}
