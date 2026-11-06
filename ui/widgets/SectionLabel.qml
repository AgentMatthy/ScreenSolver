import QtQuick
import qs.config

// Small muted heading above a group of settings.
Text {
    readonly property var theme: Config.options.theme

    topPadding: 6
    color: theme.muted
    font.family: theme.fontFamily || font.family
    font.pixelSize: theme.fontSize - 3
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 1
    elide: Text.ElideRight
}
