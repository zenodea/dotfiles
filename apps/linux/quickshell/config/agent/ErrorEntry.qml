import QtQuick
import qs.style
import qs.widgets

Label {
    required text

    width: ListView.view.width
    wrapMode: Text.Wrap
    color: Theme.red
    font.pixelSize: 13
}
