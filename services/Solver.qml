pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.config
import qs.services.providers

// Orchestrates the pipeline:  capture -> provider -> answer.
// The UI only observes this object's state.
Singleton {
    id: root

    // "idle" | "hub" | "settings" | "capturing" | "thinking" | "done" | "error"
    //   hub      = the small launcher dot shown on the first keypress
    //   settings = the settings card
    property string state: "idle"
    property string answer: ""
    // What the window shows: `answer` itself, or rendered HTML when `html` is true
    // (Markdown + LaTeX formulas turned into SVG images, see services/Latex.qml).
    property string display: ""
    property bool html: false
    property string error: ""
    // Name of the monitor the screenshot was taken on (UI shows up there).
    property string monitor: ""
    property real startedAt: 0
    property real finishedAt: 0

    // True while capturing a solve that was launched from the hub: the dot stays on screen
    // (it's tiny and gets kicked into its thinking pulse) instead of blinking out and back.
    property bool keepDot: false

    readonly property Provider provider: Providers.get(Config.options.provider)
    readonly property bool visible: state === "hub"
        || state === "settings"
        || (state === "capturing" && keepDot)
        || state === "thinking"
        || state === "done"
        || state === "error"
    readonly property bool busy: state === "capturing" || state === "thinking"

    // Start a fresh solve. Cancels anything in flight.
    function solve() {
        const wasVisible = root.visible;
        root.keepDot = root.state === "hub";
        root._abort();
        root._clear();
        root.state = "capturing"; // hides the window (except the hub dot, see keepDot)
        root.startedAt = Date.now();

        const delay = wasVisible ? Config.options.capture.hideDelayMs : 0;
        if (delay > 0) {
            captureDelay.interval = delay;
            captureDelay.restart();
        } else {
            root._capture();
        }
    }

    // Keybind-friendly, one key for everything:
    //   idle -> hub,  hub -> solve,  anything showing -> dismiss.
    function toggle() {
        if (root.state === "idle") root.hub();
        else if (root.state === "hub") root.solve();
        else if (root.state !== "capturing") root.dismiss();
    }

    // Show the launcher dot (hover it for solve / settings).
    function hub() {
        root._abort();
        root._clear();
        root.monitor = Capture.focusedMonitor;
        root.state = "hub";
    }

    // Open the settings card (stays on the current monitor if already showing).
    function settings() {
        if (!root.visible) root.monitor = Capture.focusedMonitor;
        root._abort();
        root.state = "settings";
    }

    function dismiss() {
        root._abort();
        root.state = "idle";
    }

    function _clear() {
        root.answer = "";
        root.display = "";
        root.html = false;
        root.error = "";
    }

    function _abort() {
        captureDelay.stop();
        Latex.cancel();
        Capture.cancel();
        root.provider?.cancel();
    }

    function _fail(message: string) {
        root.error = message;
        root.finishedAt = Date.now();
        root.state = "error";
    }

    function _capture() {
        if (!root.provider) {
            root._fail(`Unknown provider "${Config.options.provider}". Available: ${Providers.keys.join(", ")}`);
            return;
        }
        const problem = root.provider.validate();
        if (problem) {
            root.monitor = Capture.focusedMonitor;
            root._fail(problem);
            return;
        }

        const c = Config.options.capture;
        const started = Capture.capture({
            mode: c.mode,
            format: c.format,
            quality: c.jpegQuality,
            scale: c.scale
        });
        if (!started) console.warn("[solver] capture already in progress");
    }

    Timer {
        id: captureDelay
        repeat: false
        onTriggered: root._capture()
    }

    Connections {
        target: Capture

        function onCaptured(result) {
            if (root.state !== "capturing") return;
            root.monitor = result.monitor || Capture.focusedMonitor;
            root.state = "thinking";
            root.provider.solve({
                prompt: Config.options.prompt.user,
                systemPrompt: Config.options.prompt.system
                    + (Latex.enabled ? "\n\n" + Latex.guide : ""),
                imageBase64: result.base64,
                mimeType: result.mimeType
            });
        }

        function onFailed(message) {
            if (root.state !== "capturing") return;
            // A cancelled region selection just means "never mind".
            if (message === "Selection cancelled") {
                root.state = "idle";
                return;
            }
            root.monitor = Capture.focusedMonitor;
            root._fail(message);
        }
    }

    Connections {
        target: root.provider

        function onSucceeded(text) {
            if (root.state !== "thinking") return;
            root.answer = text;
            // Formulas get rendered first; the dot keeps pulsing meanwhile (~50-200 ms).
            if (Latex.enabled && Latex.hasMath(text)) {
                Latex.render(text, html => {
                    if (root.state !== "thinking" || root.answer !== text) return;
                    root.display = html || text;
                    root.html = html !== "";
                    root._done();
                });
            } else {
                root.display = text;
                root.html = false;
                root._done();
            }
        }

        function onFailed(message) {
            if (root.state !== "thinking") return;
            root._fail(message);
        }
    }

    function _done() {
        root.finishedAt = Date.now();
        root.state = "done";
        if (Config.options.window.copyAnswer)
            root.copy();
    }

    function copy() {
        const text = root.state === "error" ? root.error : root.answer;
        if (text) Quickshell.execDetached(["wl-copy", "--", text]);
    }
}
