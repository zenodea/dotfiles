import QtQuick
import qs.style

Text {
    visible: text !== ""
    color: Theme.muted
    font.family: Theme.fontMono
    font.pixelSize: 11
    renderType: Text.NativeRendering
}
