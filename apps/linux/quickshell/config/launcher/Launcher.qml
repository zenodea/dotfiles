pragma ComponentBehavior: Bound

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
    property string lastMode: "apps"
    readonly property bool session: mode === "session"
    readonly property string mode: Panels.launcher || lastMode
    property string query: ""

    readonly property var modes: [
        {
            id: "apps",
            label: "Apps"
        },
        {
            id: "themes",
            label: "Themes"
        },
        {
            id: "fonts",
            label: "Fonts"
        },
        {
            id: "wallpapers",
            label: "Wallpapers"
        },
        {
            id: "session",
            label: "Session"
        }
    ]

    readonly property var sessionItems: [
        {
            name: "Lock",
            icon: "󰌾",
            command: ["hyprlock"]
        },
        {
            name: "Suspend",
            icon: "󰤄",
            command: ["systemctl", "suspend"]
        },
        {
            name: "Logout",
            icon: "󰍃",
            command: ["hyprctl", "dispatch", "exit"]
        },
        {
            name: "Reboot",
            icon: "󰑓",
            command: ["systemctl", "reboot"]
        },
        {
            name: "Shutdown",
            icon: "󰐥",
            command: ["systemctl", "poweroff"]
        }
    ]

    readonly property var results: {
        const q = query.trim().toLowerCase();
        const matches = name => !q || name.toLowerCase().includes(q);

        if (mode === "apps")
            return DesktopEntries.applications.values.filter(a => !a.noDisplay && (matches(a.name) || matches(a.comment ?? ""))).sort((a, b) => a.name.localeCompare(b.name)).slice(0, 60).map(a => ({
                        kind: "app",
                        name: a.name,
                        sub: a.genericName || a.comment || "",
                        entry: a
                    }));

        if (mode === "themes")
            return Dotfiles.themes.filter(t => matches(t.name)).map(t => ({
                        kind: "theme",
                        name: t.name,
                        sub: t.appearance,
                        theme: t,
                        current: t.name === Dotfiles.currentTheme
                    }));

        if (mode === "fonts")
            return Dotfiles.fonts.filter(matches).map(f => ({
                        kind: "font",
                        name: f,
                        sub: "",
                        current: f === Dotfiles.currentFont
                    }));

        if (mode === "wallpapers")
            return Dotfiles.wallpapers.filter(w => /\.(png|jpe?g|webp|avif|bmp|gif)$/i.test(w)).filter(matches).map(w => ({
                        kind: "wallpaper",
                        name: w,
                        sub: ""
                    }));

        if (mode === "session")
            return sessionItems.filter(s => matches(s.name)).map(s => ({
                        kind: "session",
                        name: s.name,
                        icon: s.icon,
                        sub: "",
                        command: s.command
                    }));

        return [];
    }

    function activate(item: var): void {
        if (!item)
            return;
        if (item.kind === "app")
            item.entry.execute();
        else if (item.kind === "theme")
            Dotfiles.apply("theme", item.name);
        else if (item.kind === "font")
            Dotfiles.apply("font", item.name);
        else if (item.kind === "wallpaper")
            Dotfiles.apply("wallpaper", item.name);
        else if (item.kind === "session")
            Quickshell.execDetached(item.command);

        Panels.close();
    }

    x: Metrics.strip
    width: parent.width - Metrics.strip * 2
    height: shown ? Metrics.launcherHeight : 0
    y: parent.height - Metrics.strip - height

    visible: height > 0
    clip: true

    Behavior on height {
        NumberAnimation {
            duration: Metrics.morphDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: Metrics.emphasized
        }
    }

    function step(direction: string): void {
        const forward = direction === "down" || direction === "right";
        if (session || direction === "right" || direction === "left")
            forward ? list.moveCurrentIndexRight() : list.moveCurrentIndexLeft();
        else
            forward ? list.moveCurrentIndexDown() : list.moveCurrentIndexUp();
        list.positionViewAtIndex(list.currentIndex, GridView.Contain);
    }

    onShownChanged: {
        if (shown) {
            query = "";
            input.text = "";
            list.currentIndex = 0;
            list.positionViewAtBeginning();
            input.forceActiveFocus();
            focusAgain.tries = 0;
            focusAgain.restart();
        }
    }

    Timer {
        id: focusAgain

        property int tries: 0

        interval: 50
        repeat: true
        onTriggered: {
            if (!root.shown || input.activeFocus || tries >= 8) {
                tries = 0;
                stop();
                return;
            }
            tries++;
            input.forceActiveFocus();
        }
    }

    onModeChanged: {
        if (Panels.launcher !== "")
            lastMode = Panels.launcher;
        query = "";
        input.text = "";
        list.currentIndex = 0;
        list.positionViewAtBeginning();
        if (shown)
            input.forceActiveFocus();
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

    Keys.onEscapePressed: Panels.close()

    Column {
        y: root.height - Metrics.launcherHeight
        width: root.width
        height: Metrics.launcherHeight

        Item {
            width: parent.width
            height: Metrics.launcherHeader

            Row {
                id: chips

                height: parent.height

                Repeater {
                    model: root.modes

                    Rectangle {
                        id: chip

                        required property var modelData

                        readonly property bool active: root.mode === modelData.id

                        width: 118
                        height: chips.height
                        color: chipArea.containsMouse && !active ? Theme.alpha(Theme.fg, 0.07) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: chip.modelData.label
                            color: chip.active ? Theme.accent : Theme.muted
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            renderType: Text.NativeRendering
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: Metrics.borderWidth * 2
                            color: Theme.accent
                            visible: chip.active
                        }

                        MouseArea {
                            id: chipArea

                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                Panels.launcher = chip.modelData.id;
                                input.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            Rectangle {
                x: chips.width
                width: Metrics.borderWidth
                height: parent.height
                color: Theme.alpha(Theme.fg, 0.15)
            }

            TextInput {
                id: input

                x: chips.width + Metrics.drawerPadding
                width: parent.width - x - Metrics.drawerPadding
                height: parent.height
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.fgBright
                font.family: Theme.fontMono
                font.pixelSize: 14
                selectionColor: Theme.alpha(Theme.accent, 0.35)
                selectedTextColor: Theme.fgBright
                clip: true

                onTextChanged: {
                    root.query = text;
                    list.currentIndex = 0;
                    list.positionViewAtBeginning();
                    Panels.launcherByHover = false;
                }

                Keys.onEscapePressed: Panels.close()
                Keys.onDownPressed: root.step("down")
                Keys.onUpPressed: root.step("up")
                Keys.onPressed: event => {
                    if (!(event.modifiers & Qt.ControlModifier))
                        return;
                    if (event.key === Qt.Key_J)
                        root.step("down");
                    else if (event.key === Qt.Key_K)
                        root.step("up");
                    else if (event.key === Qt.Key_L)
                        root.step("right");
                    else if (event.key === Qt.Key_H)
                        root.step("left");
                    else
                        return;
                    event.accepted = true;
                }
                Keys.onReturnPressed: root.activate(root.results[list.currentIndex])
                Keys.onEnterPressed: root.activate(root.results[list.currentIndex])
                Keys.onTabPressed: {
                    const i = root.modes.findIndex(m => m.id === root.mode);
                    Panels.launcher = root.modes[(i + 1) % root.modes.length].id;
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text === ""
                    text: `Search ${root.mode}…`
                    color: Theme.alpha(Theme.muted, 0.7)
                    font: input.font
                    renderType: Text.NativeRendering
                }
            }
        }

        Rectangle {
            width: parent.width
            height: Metrics.borderWidth
            color: Theme.alpha(Theme.fg, 0.15)
        }

        GridView {
            id: list

            width: parent.width
            height: Metrics.launcherHeight - Metrics.launcherHeader - Metrics.borderWidth
            cellWidth: root.session ? 170 : Metrics.launcherCellWidth
            cellHeight: root.session ? height : Metrics.launcherCellHeight
            leftMargin: root.session ? Math.max(0, (width - root.results.length * cellWidth) / 2) : 0
            flow: GridView.FlowTopToBottom
            model: root.results
            clip: true
            currentIndex: 0
            keyNavigationEnabled: false
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: cell

                required property int index
                required property var modelData

                readonly property bool selected: list.currentIndex === index

                width: list.cellWidth
                height: list.cellHeight
                color: selected ? Theme.alpha(Theme.accent, 0.15) : cellArea.containsMouse ? Theme.alpha(Theme.fg, 0.07) : "transparent"

                Behavior on color {
                    ColorAnimation {
                        duration: Metrics.shortAnim
                    }
                }

                Rectangle {
                    width: 2
                    height: parent.height
                    color: Theme.accent
                    visible: (cell.modelData.current ?? false) && !root.session
                }

                Column {
                    anchors.centerIn: parent
                    visible: root.session
                    spacing: 10

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: cell.modelData.icon ?? ""
                        color: cell.selected ? Theme.accent : Theme.fg
                        font.family: Metrics.iconFont
                        font.pixelSize: 40
                        renderType: Text.NativeRendering

                        Behavior on color {
                            ColorAnimation {
                                duration: Metrics.shortAnim
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: cell.modelData.name
                        color: cell.selected ? Theme.accent : Theme.muted
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                        renderType: Text.NativeRendering
                    }
                }

                Row {
                    visible: !root.session
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Metrics.popoutPadding
                    anchors.rightMargin: Metrics.popoutPadding
                    spacing: Metrics.gap + 2

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: cell.modelData.kind === "app"
                        source: cell.modelData.kind === "app" ? Quickshell.iconPath(cell.modelData.entry.icon, true) : ""
                        width: 22
                        height: 22
                        sourceSize.width: 44
                        sourceSize.height: 44
                        asynchronous: true
                    }

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: cell.modelData.kind === "wallpaper"
                        source: cell.modelData.kind === "wallpaper" ? Dotfiles.wallpaperPath(cell.modelData.name) : ""
                        width: 56
                        height: 32
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 112
                        sourceSize.height: 64
                        asynchronous: true
                        cache: true
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: cell.modelData.kind === "theme"
                        spacing: 2

                        Rectangle {
                            width: 10
                            height: 22
                            color: cell.modelData.theme?.bg ?? "transparent"
                        }

                        Rectangle {
                            width: 10
                            height: 22
                            color: cell.modelData.theme?.fg ?? "transparent"
                        }

                        Rectangle {
                            width: 10
                            height: 22
                            color: cell.modelData.theme?.accent ?? "transparent"
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: cell.modelData.kind === "session"
                        text: cell.modelData.icon ?? ""
                        color: Theme.fg
                        font.family: Metrics.iconFont
                        font.pixelSize: 15
                        renderType: Text.NativeRendering
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 80
                        spacing: 0

                        Text {
                            width: parent.width
                            text: cell.modelData.name
                            color: Theme.fg
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            renderType: Text.NativeRendering
                        }

                        Text {
                            width: parent.width
                            visible: (cell.modelData.sub ?? "") !== ""
                            text: cell.modelData.sub ?? ""
                            color: Theme.muted
                            font.family: Theme.fontMono
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            renderType: Text.NativeRendering
                        }
                    }
                }

                MouseArea {
                    id: cellArea

                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        list.currentIndex = cell.index;
                        root.activate(cell.modelData);
                    }
                }
            }
        }
    }
}
