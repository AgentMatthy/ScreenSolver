import QtQuick

// Base type for AI providers. Subclass it (see OpenRouter.qml) and register
// the new provider in Providers.qml.
//
// Contract:
//   solve(request)  request = { prompt, systemPrompt, imageBase64, mimeType }
//                   must eventually emit exactly one of succeeded/failed,
//                   unless cancel() is called first.
//   cancel()        abort the in-flight request silently.
QtObject {
    id: root

    // Unique key used in config ("provider": "<key>").
    property string key
    // Human-readable label for the UI.
    property string displayName: key
    // Model identifier shown in the UI.
    property string model: ""
    property bool busy: false

    signal succeeded(string text)
    signal failed(string message)

    // Returns "" when ready, otherwise a message explaining what's missing.
    function validate(): string {
        return "";
    }

    function solve(request) {
        root.failed(`Provider "${root.key}" does not implement solve()`);
    }

    function cancel() {}
}
