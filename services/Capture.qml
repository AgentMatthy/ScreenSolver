pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.config

// Takes a screenshot with grim and hands it back as base64.
//
// Usage:  Capture.capture({ mode, format, quality, scale })
// Emits:  captured(result)  result = { base64, mimeType, monitor }
//         failed(message)
Singleton {
    id: root

    readonly property bool busy: proc.running
    property var _pending: null

    signal captured(var result)
    signal failed(string message)

    readonly property string focusedMonitor: Hyprland.focusedMonitor?.name ?? ""

    // Returns false if a capture is already in progress.
    function capture(opts): bool {
        if (proc.running) return false;

        const o = opts ?? {};
        const mode = o.mode ?? "focused";
        const format = o.format === "jpeg" || o.format === "jpg" ? "jpeg" : "png";
        const monitor = mode === "focused" ? root.focusedMonitor : "";

        root._pending = {
            mimeType: format === "jpeg" ? "image/jpeg" : "image/png",
            monitor: monitor
        };

        proc.command = ["bash", "-c", root._script, "capture",
            mode, monitor, format, String(o.quality ?? 85), String(o.scale ?? 0)];
        proc.running = true;
        return true;
    }

    function cancel() {
        root._pending = null;
        proc.running = false;
    }

    // $1 mode, $2 monitor, $3 format, $4 jpeg quality, $5 scale
    readonly property string _script: `
set -o pipefail
mode="$1"; monitor="$2"; fmt="$3"; quality="$4"; scale="$5"
args=(-t "$fmt")
[ "$fmt" = jpeg ] && args+=(-q "$quality")
[ "$scale" != 0 ] && args+=(-s "$scale")
case "$mode" in
  region)
    geom="$(slurp)" || { echo "region selection cancelled" >&2; exit 130; }
    args+=(-g "$geom") ;;
  all) ;;
  *) [ -n "$monitor" ] && args+=(-o "$monitor") ;;
esac
grim "\${args[@]}" - | base64 -w0
`

    Process {
        id: proc

        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }

        onExited: (code, status) => {
            const pending = root._pending;
            root._pending = null;
            if (!pending) return; // cancelled

            const data = out.text.trim();
            if (code !== 0 || data.length === 0) {
                const msg = err.text.trim() || `grim exited with code ${code}`;
                root.failed(code === 130 ? "Selection cancelled" : `Screenshot failed: ${msg}`);
                return;
            }
            root.captured({
                base64: data,
                mimeType: pending.mimeType,
                monitor: pending.monitor
            });
        }
    }
}
