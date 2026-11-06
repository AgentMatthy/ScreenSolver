pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Turns a Markdown answer that contains LaTeX into Qt rich text (HTML + SVG formulas).
// The heavy lifting happens in bin/screensolver-latex (MicroTeX + md4c).
//
// Usage:  Latex.render(markdown, html => ...)   html === "" means "show the Markdown as-is"
Singleton {
    id: root

    readonly property bool enabled: Config.options.latex.enabled && Config.options.window.markdown
    property var _callback: null

    // Appended to the system prompt while LaTeX rendering is on.
    readonly property string guide: `Math formatting: the answer is rendered as Markdown with LaTeX math (MicroTeX, an amsmath-like subset).
- Inline math: wrap in single dollars with no space just inside them, e.g. $x^2 + 1$ or $\\frac{a}{b}$. \\( ... \\) also works.
- Display math: put $$ ... $$ on its own line(s), separated from surrounding text by blank lines.
- Multi-line derivations: one $$ block containing \\begin{aligned} ... \\end{aligned} with & alignment and \\\\ line breaks. Piecewise functions: \\begin{cases}. Matrices: pmatrix / bmatrix / vmatrix.
- Available: \\frac \\dfrac \\tfrac \\sqrt[n]{} \\sum \\prod \\int \\iint \\oint \\lim with _ and ^ limits, \\left( \\right), \\binom, \\vec, \\hat, \\bar, \\overline, \\underbrace{}_{}, \\overbrace, \\boxed, \\cancel, \\text{}, \\operatorname{}, \\mathbb, \\mathbf, \\boldsymbol, \\mathcal, \\mathrm, \\xrightarrow, Greek letters and the usual relation/arrow symbols.
- Do NOT use \\tag, \\label, equation numbering, \\SI/\\si, \\ce, \\usepackage, \\newcommand or other preamble/package commands.
- Write a literal dollar sign (money) as \\$. Never put math inside code blocks or backticks.
- Use math only for actual mathematics; plain numbers, units and short results can stay plain text. Put the final result in \\boxed{} when it is a formula or number derived by calculation.`

    // Cheap pre-check so plain answers skip the subprocess entirely.
    function hasMath(text: string): bool {
        return /\$[^\s$]|\\\(|\\\[|\\begin\{/.test(text);
    }

    function render(markdown: string, callback) {
        root.cancel();
        root._callback = callback;

        const theme = Config.options.theme;
        const screen = Quickshell.screens.find(s => s.name === Solver.monitor) ?? Quickshell.screens[0];
        const job = {
            text: markdown,
            binary: Config.options.latex.binary,
            cacheDir: Paths.latexCacheDir,
            fg: theme.foreground,
            fontPx: theme.fontSize + 1,
            scale: Config.options.latex.scale,
            xHeightPx: metrics.xHeight,
            dpr: screen?.devicePixelRatio ?? 1,
            // Matches the answer text width (card width minus its padding).
            maxWidth: Config.options.window.width - 28
        };
        proc.command = [Paths.latexScript, JSON.stringify(job)];
        proc.running = true;
        timeout.interval = Config.options.latex.timeoutMs;
        timeout.restart();
    }

    function cancel() {
        root._callback = null;
        timeout.stop();
        proc.running = false;
    }

    function _finish(html: string) {
        const cb = root._callback;
        root._callback = null;
        timeout.stop();
        if (cb) cb(html);
    }

    FontMetrics {
        id: metrics
        font.family: Config.options.theme.fontFamily || Qt.application.font.family
        font.pixelSize: Config.options.theme.fontSize + 1
    }

    Timer {
        id: timeout
        repeat: false
        onTriggered: {
            console.warn("[latex] renderer timed out, showing plain Markdown");
            proc.running = false;
            root._finish("");
        }
    }

    Process {
        id: proc

        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }

        onExited: (code, status) => {
            if (!root._callback) return; // cancelled / timed out
            const result = out.text;
            if (code !== 0) {
                console.warn(`[latex] renderer exited with ${code}: ${err.text.trim()}`);
                root._finish("");
            } else {
                // The script echoes the input back untouched when there was nothing to render.
                root._finish(result.startsWith("<style>") ? result : "");
            }
        }
    }
}
