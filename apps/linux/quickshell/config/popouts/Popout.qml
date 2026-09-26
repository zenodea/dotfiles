pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.style
import qs.services
import qs.widgets

Item {
    id: root

    required property ShellScreen screen
    required property real maxX

    readonly property bool shown: Popouts.open && Popouts.screen === screen
    readonly property alias hitArea: hitArea

    readonly property real targetHeight: shown ? loader.implicitHeight + Metrics.popoutPadding * 2 : 0
    readonly property real targetWidth: Popouts.fixedWidth > 0 ? Popouts.fixedWidth : Math.max(Metrics.popoutMinWidth, loader.implicitWidth + Metrics.popoutPadding * 2)

    width: targetWidth
    x: Math.max(0, Math.min(maxX - targetWidth, Popouts.anchorX - targetWidth / 2))

    y: Metrics.barHeight
    height: targetHeight

    visible: morphing
    clip: true

    readonly property bool morphing: height > 0

    Behavior on x {
        enabled: root.morphing

        Morph {}
    }

    Behavior on width {
        enabled: root.morphing

        Morph {}
    }

    Behavior on height {
        Morph {}
    }

    Connections {
        function onSourceChanged(): void {
            if (root.shown && Popouts.source)
                contentIn.restart();
        }

        target: Popouts
    }

    NumberAnimation {
        id: contentIn

        target: loader
        property: "opacity"
        from: 0.35
        to: 1
        duration: Metrics.shortAnim
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered)
                Popouts.stay();
        }
    }

    Item {
        id: hitArea

        width: root.shown ? root.targetWidth : 0
        height: root.targetHeight
    }

    Loader {
        id: loader

        anchors.centerIn: parent
        sourceComponent: Popouts.content || fallback

        onStatusChanged: {
            if (status === Loader.Error)
                console.warn("popout content failed for", Popouts.title, "->", sourceComponent);
        }

        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Metrics.shortAnim
            }
        }
    }

    Component {
        id: fallback

        Column {
            spacing: 2

            PopoutTitle {
                text: Popouts.title
            }

            PopoutLabel {
                text: Popouts.detail
            }

            Item {
                width: 1
                height: 4
                visible: Popouts.level >= 0
            }

            PopoutLevel {
                visible: Popouts.level >= 0
                level: Popouts.level
            }
        }
    }
}
