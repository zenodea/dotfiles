import QtQuick
import qs.style

TextEdit {
    required text

    width: ListView.view.width
    readOnly: true
    selectByMouse: true
    wrapMode: TextEdit.Wrap
    textFormat: TextEdit.MarkdownText
    color: Theme.fg
    selectionColor: Theme.alpha(Theme.accent, 0.35)
    font.family: Theme.fontMono
    font.pixelSize: 14
    renderType: Text.NativeRendering
    onLinkActivated: link => Qt.openUrlExternally(link)
}
