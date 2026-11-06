pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// User configuration, backed by ~/.config/screensolver/config.json.
//
// - The file is created with defaults on first run.
// - It is watched; edits are hot-reloaded.
// - Missing keys fall back to the defaults declared below, so adding a new
//   option is just: add a property here, read it via Config.options.<...>.
Singleton {
    id: root

    property alias options: adapter
    property bool ready: false

    // Ensure the config directory exists (private, since it holds an API key)
    // before pointing the FileView at it.
    Process {
        running: true
        command: ["sh", "-c", 'mkdir -p "$1" && chmod 700 "$1"', "sh", Paths.configDir]
        onExited: fileView.path = Paths.configFile
    }

    // Coalesce bursts of edits (e.g. a color change that also re-derives tones,
    // or holding a stepper) into a single write.
    Timer {
        id: saveTimer
        interval: 80
        onTriggered: fileView.writeAdapter()
    }
    // Ignore the file-watch echo of our own write.
    Timer {
        id: echoTimer
        interval: 400
    }

    FileView {
        id: fileView

        watchChanges: true
        // Skip reloads while our own (debounced) write is pending or just landed,
        // otherwise reading an intermediate file would clobber newer in-memory edits.
        onFileChanged: if (!saveTimer.running && !echoTimer.running) reload()
        onAdapterUpdated: saveTimer.restart()
        // Writes replace the file (umask perms); it holds an API key, so keep it private.
        onSaved: {
            echoTimer.restart();
            Quickshell.execDetached(["chmod", "600", Paths.configFile]);
        }
        onLoaded: root.ready = true
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                console.info(`[config] creating default config at ${Paths.configFile}`);
                writeAdapter();
                // Will hold an API key: keep it private (dir is already 700).
                Quickshell.execDetached(["sh", "-c", 'sleep 1; chmod 600 "$1"', "sh", Paths.configFile]);
            } else {
                console.warn(`[config] failed to load ${Paths.configFile}: ${FileViewError.toString(error)}`);
            }
            root.ready = true;
        }

        JsonAdapter {
            id: adapter

            // Which provider (see services/providers/Providers.qml) handles requests.
            property string provider: "openrouter"

            property JsonObject prompt: JsonObject {
                property string system: "You are a precise problem solver. The user sends a screenshot of their screen. Identify the question, task or problem shown and solve it. Respond with the most concise answer possible: the final answer only, with at most one short line of justification if truly needed. No preamble."
                property string user: "Solve whatever is on the screen, and provide the most concise answer possible."
            }

            property JsonObject capture: JsonObject {
                // "focused" (focused monitor) | "all" (every monitor) | "region" (select with slurp)
                property string mode: "focused"
                // "png" | "jpeg" (jpeg = smaller upload, faster)
                property string format: "png"
                property int jpegQuality: 85
                // Output scale passed to grim (-s). 0 = grim default.
                property real scale: 0
                // Delay before capturing when the answer window was visible
                // (lets the compositor finish hiding it).
                property int hideDelayMs: 250
            }

            property JsonObject openrouter: JsonObject {
                // Falls back to $OPENROUTER_API_KEY when empty.
                property string apiKey: ""
                // Active model.
                property string model: "google/gemini-3.8-flash"
                // Models offered in the settings window (the active one is always shown too).
                // Defaults to the built-in catalog in Models.qml.
                property var models: Models.ids
                property string endpoint: "https://openrouter.ai/api/v1/chat/completions"
                property int maxTokens: 1024
                property real temperature: 0.2
                property int timeoutMs: 90000
                // Merged verbatim into the request body (e.g. {"reasoning": {"effort": "low"}}).
                property var extraBody: ({})
            }

            property JsonObject window: JsonObject {
                // "top-left" | "top" | "top-right" | "bottom-left" | "bottom" | "bottom-right" | "center"
                property string position: "top-right"
                property int width: 420
                property int maxHeight: 520
                property int margin: 18
                // Auto-dismiss after showing an answer. 0 = never.
                property int autoHideMs: 0
                // How long the hub dot (first keypress) stays up when not hovered. 0 = until dismissed.
                property int hubTimeoutMs: 5000
                property bool copyAnswer: false
                property bool markdown: true
            }

            property JsonObject latex: JsonObject {
                // Render $...$ / $$...$$ math in answers (needs window.markdown).
                // The model is told how to write math only while this is on.
                property bool enabled: true
                // MicroTeX CLI (needs its res/ directory next to it).
                property string binary: "/opt/MicroTeX/LaTeX"
                // Formula size relative to the answer text.
                property real scale: 1.1
                // Give up and show the raw answer if rendering takes longer than this.
                property int timeoutMs: 6000
            }

            property JsonObject theme: JsonObject {
                property string background: "#000000"
                property string surface: "#1f1f26"
                property string foreground: "#e8e8ee"
                property string muted: "#8a8a99"
                property string accent: "#8ab4ff"
                property string error: "#ff7a7a"
                property int radius: 14
                property string fontFamily: ""
                property int fontSize: 14
            }
        }
    }
}
