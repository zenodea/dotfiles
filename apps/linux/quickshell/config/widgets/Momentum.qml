import QtQuick

WheelHandler {
    id: root

    readonly property Flickable view: (parent as Flickable) ?? (parent?.parent as Flickable)
    readonly property bool sideways: orientation === Qt.Horizontal
    readonly property real friction: 3.5
    readonly property real fastest: 6000
    readonly property real slowest: 12
    readonly property real threshold: 50
    readonly property int window: 80

    property var samples: []
    property real velocity: 0
    property real carried: 0
    property real expected: 0

    readonly property FrameAnimation glide: FrameAnimation {
        onTriggered: {
            if (Math.abs(root.position() - root.expected) > 0.5) {
                root.halt();
                return;
            }
            const decay = Math.exp(-root.friction * Math.min(frameTime, 0.05));
            const wanted = root.expected + root.velocity * (1 - decay) / root.friction;
            const target = root.limit(wanted);
            if (root.sideways)
                root.view.contentX = target;
            else
                root.view.contentY = target;
            root.expected = root.position();
            root.velocity *= decay;
            if (target !== wanted || Math.abs(root.velocity) < root.slowest)
                root.halt();
        }
    }

    signal settled

    function position(): real {
        return sideways ? view.contentX : view.contentY;
    }

    function limit(value: real): real {
        const low = sideways ? view.originX - view.leftMargin : view.originY - view.topMargin;
        const high = sideways ? view.originX + view.contentWidth + view.rightMargin - view.width : view.originY + view.contentHeight + view.bottomMargin - view.height;
        return Math.max(low, Math.min(value, Math.max(low, high)));
    }

    function halt(): void {
        if (!glide.running)
            return;
        glide.stop();
        velocity = 0;
        settled();
    }

    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    blocking: false

    onWheel: event => {
        const now = Date.now();
        const recent = samples.filter(s => now - s.t <= window);
        if (event.phase === Qt.ScrollUpdate) {
            if (glide.running) {
                carried = velocity;
                halt();
            }
            recent.push({
                t: now,
                x: event.pixelDelta.x,
                y: event.pixelDelta.y
            });
            samples = recent;
            return;
        }
        const kept = carried;
        samples = [];
        carried = 0;
        if (event.phase !== Qt.ScrollEnd) {
            halt();
            return;
        }
        if (recent.length < 3)
            return;
        const span = (recent[recent.length - 1].t - recent[0].t) / 1000;
        if (span <= 0)
            return;
        let x = 0;
        let y = 0;
        for (const s of recent.slice(1)) {
            x += s.x;
            y += s.y;
        }
        if ((Math.abs(x) > Math.abs(y)) !== sideways)
            return;
        let speed = -(sideways ? x : y) / span;
        if (kept * speed > 0 && Math.abs(speed) > Math.abs(kept) / 2)
            speed += kept;
        if (Math.abs(speed) < threshold)
            return;
        velocity = Math.max(-fastest, Math.min(speed, fastest));
        expected = position();
        glide.restart();
    }
}
