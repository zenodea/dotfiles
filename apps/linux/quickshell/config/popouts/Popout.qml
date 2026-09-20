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

    readonly property real targetWidth: Math.max(Metrics.popoutMinWidth, loader.implicitWidth + Metrics.popoutPadding * 2)

    width: targetWidth
    x: Math.max(Metrics.strip, Math.min(maxX - targetWidth, Popouts.anchorX - targetWidth / 2))

    y: Metrics.barHeight
    height: shown ? loader.implicitHeight + Metrics.popoutPadding * 2 : 0

    visible: height > 0
    clip: true

    readonly property bool morphing: height > 0

    Behavior on x {
        enabled: root.morphing

        NumberAnimation {
            duration: Metrics.morphDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: Metrics.emphasized
        }
    }

    Behavior on width {
        enabled: root.morphing

        NumberAnimation {
            duration: Metrics.morphDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: Metrics.emphasized
        }
    }

    Behavior on height {
        NumberAnimation {
            duration: Metrics.morphDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: Metrics.emphasized
        }
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
                Popouts.hold(root);
        }
    }

    Item {
        id: hitArea

        width: root.shown ? root.targetWidth : 0
        height: root.shown ? loader.implicitHeight + Metrics.popoutPadding * 2 : 0
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
