import QtQuick
import qs.lock
import qs.services
import qs.style
import qs.widgets

Column {
    spacing: 8

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab)
            Greeter.cycle(-1);
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab)
            Greeter.cycle(1);
        else if (Greeter.preview && event.key === Qt.Key_Q && event.modifiers & Qt.ControlModifier)
            Qt.quit();
        else
            return;
        event.accepted = true;
    }

    Clock {
        anchors.horizontalCenter: parent.horizontalCenter
    }

    Item {
        width: 1
        height: 40
    }

    PasswordField {
        anchors.horizontalCenter: parent.horizontalCenter
        auth: Greeter
    }

    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        height: 20
        text: Greeter.checking ? "checking…" : Greeter.fails > 0 ? `wrong password · ${Greeter.fails}` : Greeter.users.length > 1 ? "← → switch user" : ""
        color: Greeter.fails > 0 && !Greeter.checking ? Theme.red : Theme.muted
        font.pixelSize: 12
    }
}
