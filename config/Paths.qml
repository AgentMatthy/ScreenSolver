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
    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || `${home}/.cache`
    readonly property string cacheDir: `${cacheHome}/screensolver`
    // Rendered formula SVGs (safe to delete any time).
    readonly property string latexCacheDir: `${cacheDir}/latex`
    // Markdown + LaTeX -> HTML renderer (see bin/screensolver-latex).
    readonly property string latexScript: Quickshell.shellPath("bin/screensolver-latex")
}
