import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.services
import qs.ui

// ScreenSolver — screenshot → AI → concise answer.
//
// Trigger from anywhere (e.g. a Hyprland bind):
//   qs -p <this dir> ipc call solver solve
// or use bin/screensolver, which also starts the daemon if needed.
ShellRoot {
    id: root

    IpcHandler {
        target: "solver"

        // Take a screenshot and solve it.
        function solve(): void { Solver.solve(); }
        // Solve, or close the window if it's open.
        function toggle(): void { Solver.toggle(); }
        // Close the window / cancel the request.
        function dismiss(): void { Solver.dismiss(); }
        // Copy the current answer to the clipboard.
        function copy(): void { Solver.copy(); }
        // "idle" | "capturing" | "thinking" | "done" | "error"
        function status(): string { return Solver.state; }
        // Last answer (or error).
        function answer(): string { return Solver.state === "error" ? Solver.error : Solver.answer; }
        // Path of the config file.
        function configPath(): string { return Paths.configFile; }
    }

    LazyLoader {
        active: Solver.visible
        AnswerWindow {}
    }

    // Force config to load at startup (creates the default file on first run).
    Component.onCompleted: console.info(`[screensolver] ready, config: ${Paths.configFile}, provider: ${Config.options.provider}`)
}
