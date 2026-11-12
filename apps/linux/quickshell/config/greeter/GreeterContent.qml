import QtQuick
import qs.lock
import qs.services
import qs.style
import qs.widgets

Column {
    readonly property string hint: [Greeter.users.length > 1 ? "← → user" : "", Greeter.sessions.length > 1 ? "↑ ↓ session" : ""].filter(Boolean).join("  ·  ")

    spacing: 8

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab)
            Greeter.cycle(-1);
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab)
            Greeter.cycle(1);
        else if (event.key === Qt.Key_Up)
            Greeter.cycleSession(-1);
        else if (event.key === Qt.Key_Down)
            Greeter.cycleSession(1);
        else if (Greeter.preview && event.key === Qt.Key_Q && event.modifiers & Qt.ControlModifier)
            Qt.quit();
        else
            return;
        event.accepted = true;
    }

    Clock {
        anchors.horizontalCenter: parent.horizontalCenter
    }

    Battery {
        anchors.horizontalCenter: parent.horizontalCenter
        topPadding: 4
    }

    Item {
        width: 1
        height: 40
    }

    PasswordField {
        anchors.horizontalCenter: parent.horizontalCenter
        auth: Greeter
    }

    Info {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: Greeter.session !== null
        icon: "󰍹"
        iconColor: Theme.muted
        text: Greeter.session?.name ?? ""
    }

    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        height: 20
        text: Greeter.checking ? "checking…" : Locks.caps ? "caps lock is on" : Greeter.fails > 0 ? `wrong password · ${Greeter.fails}` : parent.hint
        color: Greeter.checking ? Theme.muted : Locks.caps ? Theme.yellow : Greeter.fails > 0 ? Theme.red : Theme.muted
        font.pixelSize: 12
    }
}
