# ScreenSolver

A tiny [Quickshell](https://quickshell.org) app: press a key → it screenshots your
screen → sends it to an AI model → shows the most concise answer in a small overlay.

## Requirements

`quickshell` (0.2+), `grim`, `bash`, `base64` (coreutils), `wl-copy` (copy), `slurp` (only for `region` mode). Hyprland (used to detect the focused monitor).

## Setup

1. Start it once (creates `~/.config/screensolver/config.json`):

   ```sh
   ./bin/screensolver status
   ```

2. Put your OpenRouter key in `~/.config/screensolver/config.json` → `openrouter.apiKey`
   (or export `OPENROUTER_API_KEY`). The file is hot-reloaded, no restart needed.

3. Hyprland (`hyprland.conf`):

   ```ini
   exec-once = ~/Dev/ScreenSolver/bin/screensolver daemon
   bind = SUPER SHIFT, S, exec, ~/Dev/ScreenSolver/bin/screensolver toggle
   ```

   `bin/screensolver` starts the daemon on demand, so `exec-once` is optional
   (it just makes the first press instant).

## Commands

`bin/screensolver <cmd>` — or directly `qs -p <dir> ipc call solver <cmd>`:

| cmd       | does                                              |
|-----------|---------------------------------------------------|
| `solve`   | screenshot + solve (default)                      |
| `toggle`  | close the window if open, otherwise `solve`       |
| `dismiss` | close the window / cancel the request             |
| `copy`    | copy the answer to the clipboard                  |
| `status`  | `idle` / `capturing` / `thinking` / `done` / `error` |
| `answer`  | print the last answer                             |

In the window: `Esc` close, `R` retry, `Ctrl+C` copy (click the window first to focus it).

## Config (`~/.config/screensolver/config.json`)

| key | default | notes |
|-----|---------|-------|
| `provider` | `"openrouter"` | which provider handles requests |
| `prompt.system` / `prompt.user` | concise-solver prompts | |
| `capture.mode` | `"focused"` | `focused` monitor, `all` monitors, `region` (slurp) |
| `capture.format` | `"png"` | `jpeg` = smaller/faster upload |
| `capture.jpegQuality` | `85` | |
| `capture.scale` | `0` | grim `-s`, relative to logical size (`0` = full res) |
| `capture.hideDelayMs` | `250` | wait for the window to hide before re-capturing |
| `openrouter.apiKey` | `""` | falls back to `$OPENROUTER_API_KEY` |
| `openrouter.model` | `"google/gemini-3.8-flash"` | any vision-capable OpenRouter model |
| `openrouter.maxTokens` / `temperature` / `timeoutMs` | `1024` / `0.2` / `90000` | |
| `openrouter.extraBody` | `{}` | merged into the request body, e.g. `{"reasoning": {"effort": "low"}}` |
| `window.position` | `"top-right"` | `top-left`, `top`, `top-right`, `bottom-*`, `center` |
| `window.width` / `maxHeight` / `margin` | `420` / `520` / `18` | |
| `window.autoHideMs` | `0` | auto-dismiss after an answer (0 = never; paused while hovered) |
| `window.copyAnswer` | `false` | copy the answer automatically |
| `window.markdown` | `true` | render answers as Markdown |
| `theme.*` | dark | colors (`#AARRGGBB` ok), `radius`, `fontFamily`, `fontSize` |

## Architecture

```
shell.qml                     entry: IPC handler + lazily-loaded window
bin/screensolver              launcher / IPC trigger for keybinds
config/
  Paths.qml                   all filesystem locations
  Config.qml                  JSON config (defaults, hot reload, auto-create)
services/
  Solver.qml                  pipeline + state machine (capture → provider → answer)
  Capture.qml                 grim/slurp screenshot → base64
  providers/
    Provider.qml              provider interface (solve / cancel / validate)
    OpenRouter.qml            OpenRouter implementation
    Providers.qml             provider registry
ui/
  AnswerWindow.qml            the overlay
```

The UI only observes `Solver`; `Solver` only talks to `Capture` and the
`Provider` interface; every tunable lives in `Config`.

**Adding a provider:** create `services/providers/Foo.qml` extending `Provider`
(set `key: "foo"`, implement `solve(request)` emitting `succeeded(text)` /
`failed(message)`), add `Foo {}` to `Providers.all`, add a `foo` `JsonObject`
to `Config.qml`, then set `"provider": "foo"`.

**Adding an option:** add a property to the relevant `JsonObject` in
`config/Config.qml` and read it via `Config.options.<section>.<name>`.
