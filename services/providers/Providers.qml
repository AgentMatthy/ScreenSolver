pragma Singleton
import QtQuick
import Quickshell

// Registry of available AI providers.
// To add one: create <Name>.qml extending Provider, instantiate it below and
// add it to `all`. Select it with "provider": "<key>" in config.json.
Singleton {
    id: root

    readonly property list<Provider> all: [
        OpenRouter {}
    ]

    function get(key: string): Provider {
        for (const p of root.all)
            if (p.key === key) return p;
        return null;
    }

    readonly property var keys: all.map(p => p.key)
}
