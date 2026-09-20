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

    property bool drawerByHover: false
    property bool launcherByHover: false

    property bool drawerPointer: false
    property bool drawerEdgePointer: false
    property bool launcherPointer: false
    property bool launcherEdgePointer: false

    property bool drawerHoverBlocked: false
    property bool launcherHoverBlocked: false

    onDrawerPointerChanged: judgeDrawer()
    onLauncherPointerChanged: judgeLauncher()

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

    readonly property bool anyOpen: drawer || launcher !== ""

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
        drawer = true;
    }

    function openLauncher(mode: string): void {
        launcherClose.stop();
        screen = focusedScreen();
        drawer = false;
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

    function hoverOpenDrawer(): void {
        drawerClose.stop();
        if (drawer || launcher !== "" || drawerHoverBlocked)
            return;
        screen = focusedScreen();
        drawerByHover = true;
        launcher = "";
        drawer = true;
    }

    function hoverOpenLauncher(): void {
        launcherClose.stop();
        if (launcher !== "" || drawer || launcherHoverBlocked)
            return;
        screen = focusedScreen();
        launcherByHover = true;
        drawer = false;
        launcher = "themes";
    }

    function close(): void {
        drawerClose.stop();
        launcherClose.stop();
        drawerHoverBlocked = drawerPointer || drawerEdgePointer;
        launcherHoverBlocked = launcherPointer || launcherEdgePointer;
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
        id: launcherClose

        interval: 350
        onTriggered: {
            root.launcher = "";
            root.launcherByHover = false;
        }
    }
}
