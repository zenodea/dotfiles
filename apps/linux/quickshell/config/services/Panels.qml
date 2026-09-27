pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    property var screen: null
    property bool drawer: false
    property string drawerTab: "dashboard"
    property string launcher: ""
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

    function focusedScreen(): var {
        const monitor = Hyprland.focusedMonitor;
        return Quickshell.screens.find(s => Hyprland.monitorFor(s) === monitor) ?? Quickshell.screens[0] ?? null;
    }

    function toggleDrawer(tab: string): void {
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
        drawer = true;
    }

    function toggleControls(tab: string): void {
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
        controls = true;
    }

    function openLauncher(mode: string): void {
        launcherClose.stop();
        screen = focusedScreen();
        drawer = false;
        controls = false;
        launcherByHover = false;
        launcher = mode || "apps";
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
        if (anyOpen || drawerHoverBlocked)
            return;
        screen = focusedScreen();
        drawerByHover = true;
        launcher = "";
        drawer = true;
    }

    function hoverOpenLauncher(): void {
        launcherClose.stop();
        if (anyOpen || launcherHoverBlocked)
            return;
        screen = focusedScreen();
        launcherByHover = true;
        drawer = false;
        launcher = "themes";
    }

    function hoverOpenControls(): void {
        controlsClose.stop();
        if (anyOpen || controlsHoverBlocked)
            return;
        screen = focusedScreen();
        controlsByHover = true;
        controls = true;
    }

    function close(): void {
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
