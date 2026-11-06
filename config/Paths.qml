pragma Singleton
import QtQuick
import Quickshell

// Central place for every filesystem location the app uses.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || `${home}/.config`
    readonly property string configDir: `${configHome}/screensolver`
    readonly property string configFile: `${configDir}/config.json`
}
