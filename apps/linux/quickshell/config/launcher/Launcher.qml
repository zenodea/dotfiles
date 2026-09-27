import QtQuick
import Quickshell
import qs.services
import qs.style
import qs.widgets

Item {
    id: root

    required property ShellScreen screen

    readonly property bool shown: Panels.launcher !== "" && Panels.screen?.name === screen?.name
    readonly property alias hitArea: hitArea
    readonly property string mode: Panels.launcher || lastMode
    readonly property bool session: mode === "session"

    property string lastMode: "apps"

    function activate(item: var): void {
        if (model.activate(item))
            Panels.close();
    }

    function reset(): void {
        header.input.text = "";
        model.query = "";
        grid.selectCurrent();
    }

    x: Metrics.strip
    width: parent.width - Metrics.strip * 2
    height: shown ? Metrics.launcherHeight : 0
    y: parent.height - Metrics.strip - height

    visible: height > 0
    clip: true

    Behavior on height {
        Morph {}
    }

    onSessionChanged: {
        if (session)
            Updates.refresh();
    }

    onShownChanged: {
        if (shown) {
            reset();
            header.input.forceActiveFocus();
            focusAgain.tries = 0;
            focusAgain.restart();
        }
    }

    onModeChanged: {
        if (Panels.launcher !== "")
            lastMode = Panels.launcher;
        if (mode === "wallpapers")
            Dotfiles.refreshWallpapers();
        else if (mode === "themes")
            Dotfiles.refreshThemes();
        reset();
        Qt.callLater(reset);
        if (shown)
            header.input.forceActiveFocus();
    }

    Keys.onEscapePressed: Panels.close()

    LauncherModel {
        id: model

        mode: root.mode
    }

    // the layer surface can take a few frames to get keyboard focus after opening
    Timer {
        id: focusAgain

        property int tries: 0

        interval: 50
        repeat: true
        onTriggered: {
            if (!root.shown || header.input.activeFocus || tries >= 8) {
                tries = 0;
                stop();
                return;
            }
            tries++;
            header.input.forceActiveFocus();
        }
    }

    Item {
        id: hitArea

        y: root.height - height
        width: root.width
        height: root.shown ? Metrics.launcherHeight : 0
    }

    HoverHandler {
        onHoveredChanged: Panels.launcherPointer = hovered
    }

    Column {
        y: root.height - Metrics.launcherHeight
        width: root.width
        height: Metrics.launcherHeight

        LauncherHeader {
            id: header

            width: parent.width
            modes: model.modes
            mode: root.mode
            onStep: direction => grid.step(direction)
            onPage: direction => grid.page(direction)
            onAccepted: root.activate(model.results[grid.currentIndex])
            onNextMode: Panels.launcher = model.nextMode()
        }

        Connections {
            target: header.input

            function onTextChanged(): void {
                model.query = header.input.text;
                grid.currentIndex = 0;
                grid.positionViewAtBeginning();
                Panels.launcherByHover = false;
            }
        }

        Rectangle {
            width: parent.width
            height: Metrics.borderWidth
            color: Theme.alpha(Theme.fg, 0.15)
        }

        ResultGrid {
            id: grid

            x: root.mode === "fonts" ? fontRows.gutter : 0
            width: parent.width - x
            height: Metrics.launcherHeight - Metrics.launcherHeader - Metrics.borderWidth - (root.session ? Metrics.launcherFooter : 0)
            mode: root.mode
            query: model.query
            results: model.results
            onActivated: item => root.activate(item)
        }

        SessionFooter {
            visible: root.session
            width: parent.width
        }
    }

    FontRows {
        id: fontRows

        visible: root.mode === "fonts"
        y: root.height - Metrics.launcherHeight + Metrics.launcherHeader + Metrics.borderWidth
        width: root.width
        height: grid.height
    }
}
