pragma ComponentBehavior: Bound

import QtQuick
import qs.style

// the launcher's results; each cell builds only the tile for the current mode
GridView {
    id: root

    property string mode: ""
    property string query: ""
    property var results: []

    readonly property bool single: mode === "session"
    readonly property bool tiles: mode === "wallpapers" || mode === "themes" || mode === "apps" || mode === "fonts"

    signal activated(var item)

    function step(direction: string): void {
        const from = currentIndex;
        const forward = direction === "down" || direction === "right";
        if (single || direction === "right" || direction === "left")
            forward ? moveCurrentIndexRight() : moveCurrentIndexLeft();
        else
            forward ? moveCurrentIndexDown() : moveCurrentIndexUp();
        if (results[currentIndex]?.kind === "blank")
            currentIndex = from;
        positionViewAtIndex(currentIndex, GridView.Contain);
    }

    function page(direction: int): void {
        const rows = single ? 1 : 2;
        const cols = Math.max(1, Math.floor(Math.floor(width / cellWidth) / 2));
        let i = Math.max(0, Math.min(results.length - 1, currentIndex + direction * cols * rows));
        while (i !== currentIndex && results[i]?.kind === "blank")
            i -= direction;
        currentIndex = i;
        positionViewAtIndex(i, GridView.Contain);
    }

    // selects the current theme/font/wallpaper, preferring mono fonts over text fonts
    function selectCurrent(): void {
        const top = results.findIndex(r => r.current && r.kind !== "text-font");
        const active = top >= 0 ? top : results.findIndex(r => r.current);
        currentIndex = Math.max(0, active);
        if (active > 0)
            positionViewAtIndex(active, GridView.Center);
        else
            positionViewAtBeginning();
    }

    cellWidth: single ? 170 : mode === "apps" ? 150 : mode === "fonts" ? Math.max(300, Math.floor(width / Math.max(1, Math.ceil(results.length / 2)))) : tiles ? Math.round(cellHeight * 16 / 9) : Math.max(320, Math.floor(width / Math.max(1, results.length)))
    cellHeight: single ? height : height / 2
    leftMargin: single ? Math.max(0, (width - results.length * cellWidth) / 2) : 0
    flow: GridView.FlowTopToBottom
    model: results
    clip: true
    currentIndex: 0
    keyNavigationEnabled: false
    boundsBehavior: Flickable.StopAtBounds

    delegate: Item {
        id: cell

        required property int index
        required property var modelData

        readonly property bool selected: root.currentIndex === index
        readonly property int inset: root.single ? 7 : root.mode === "fonts" ? 4 : 3

        width: root.cellWidth
        height: root.cellHeight

        Loader {
            x: cell.inset
            y: cell.inset
            width: parent.width - cell.inset * 2
            height: parent.height - cell.inset * 2
            active: cell.modelData.kind !== "blank"
            sourceComponent: ({
                    session: sessionTile,
                    wallpapers: wallpaperTile,
                    themes: themeTile,
                    fonts: fontTile,
                    apps: appTile
                })[root.mode] ?? null

            Component {
                id: sessionTile

                SessionTile {
                    item: cell.modelData
                    selected: cell.selected
                    hovered: area.containsMouse
                }
            }

            Component {
                id: wallpaperTile

                WallpaperTile {
                    item: cell.modelData
                    selected: cell.selected
                    hovered: area.containsMouse
                }
            }

            Component {
                id: themeTile

                ThemeTile {
                    item: cell.modelData
                    selected: cell.selected
                    hovered: area.containsMouse
                }
            }

            Component {
                id: fontTile

                FontTile {
                    item: cell.modelData
                    selected: cell.selected
                    hovered: area.containsMouse
                }
            }

            Component {
                id: appTile

                AppTile {
                    item: cell.modelData
                    selected: cell.selected
                    hovered: area.containsMouse
                    query: root.query
                }
            }
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                root.currentIndex = cell.index;
                root.activated(cell.modelData);
            }
        }
    }
}
