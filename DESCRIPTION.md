# ScreenSolver — Project Description

Single source of truth for what this app is, how it works, and how it is built.
**Keep this file up to date with every change** (features, config keys, files, behavior, conventions).

## Purpose

A small [Quickshell](https://quickshell.org) (QML) app with one job: when triggered
(e.g. by a Hyprland keybind), take a screenshot of the user's screen, send it to an
AI vision model with a "solve whatever is on the screen, as concisely as possible"
prompt, and show the answer in a small overlay window.

Configuration is expected to grow a lot, so the code is modular: every tunable lives
in one config schema, providers are pluggable, and the UI only observes state.

## Environment / dependencies

- Quickshell 0.2+ (developed on 0.3.2), Qt 6, Wayland, **Hyprland** (focused monitor detection via `Quickshell.Hyprland`).
- `grim` (screenshot), `bash`, `base64` (coreutils), `wl-copy` (clipboard), `slurp` (only for `region` capture mode).
- AI backend: **OpenRouter** (OpenAI-compatible `/chat/completions` with `image_url` data-URI input). HTTP is done with QML `XMLHttpRequest` (keeps the API key out of process argv).

## Usage

- Run: `bin/screensolver daemon` (foreground) or let the launcher start it on demand.
- Trigger: `bin/screensolver [solve|toggle|dismiss|copy|status|answer]` (default `solve`).
  The launcher starts the daemon (`qs -p <dir> -d`) if `ipc show` fails, waits up to 5s, then runs `qs -p <dir> ipc call solver <cmd>`.
- Hyprland:
  ```ini
  exec-once = ~/Dev/ScreenSolver/bin/screensolver daemon
  bind = SUPER SHIFT, S, exec, ~/Dev/ScreenSolver/bin/screensolver toggle
  ```
- **This machine's setup** (Hyprland 0.56, Lua config in `~/.config/hypr/lua/`):
  - `keybinds.lua`: `hl.bind(m("X"), exec(home .. "/Dev/ScreenSolver/bin/screensolver toggle"))` → **SUPER+X**.
  - `startup.lua`: `home .. "/Dev/ScreenSolver/bin/screensolver daemon"` in the `autostart` list.
  - The API key in `~/.config/screensolver/config.json` was copied from the older standalone script
    `~/.config/hypr/scripts/ScreenSolver.sh` (still bound to SUPER+A; separate from this app).
- IPC target `solver` (in `shell.qml`): `solve()`, `toggle()`, `dismiss()`, `copy()`, `status(): string`, `answer(): string`, `configPath(): string`.
- Window keys (after clicking it, keyboard focus is OnDemand): `Esc` close, `R` retry, `Ctrl+C` copy (when no text is selected). Header buttons: copy, retry, close.

## Architecture

```
shell.qml                     ShellRoot: IpcHandler "solver" + LazyLoader(AnswerWindow, active: Solver.visible)
bin/screensolver              bash launcher / IPC trigger
config/
  Paths.qml        (singleton) filesystem locations (XDG_CONFIG_HOME aware)
  Config.qml       (singleton) FileView + JsonAdapter schema with defaults; Config.options.<section>.<key>
services/
  Solver.qml       (singleton) pipeline + state machine: capture -> provider -> answer
  Capture.qml      (singleton) grim/slurp -> base64 via bash Process
  providers/
    Provider.qml              base type / interface for AI providers
    OpenRouter.qml            OpenRouter implementation (extends Provider)
    Providers.qml  (singleton) registry: `all` list, get(key), keys
ui/
  AnswerWindow.qml            PanelWindow overlay (wlr-layer-shell, Overlay layer)
```

Imports use Quickshell's root module system: `import qs.config`, `import qs.services`,
`import qs.services.providers`, `import qs.ui`. Singletons use `pragma Singleton` + `Singleton {}`.

Data flow / responsibilities:
- **UI only observes `Solver`** (state, answer, error, monitor, timings) and calls its functions.
- **`Solver` only talks to `Capture` and the `Provider` interface**, reading settings from `Config`.
- **Every tunable lives in `Config.qml`.**

### Solver (`services/Solver.qml`)

- `state`: `"idle" | "capturing" | "thinking" | "done" | "error"` (string, also returned over IPC).
- Properties: `answer`, `error`, `monitor` (monitor name the window shows on), `startedAt`, `finishedAt`,
  `provider` (= `Providers.get(Config.options.provider)`), `visible` (thinking/done/error), `busy` (capturing/thinking).
- `solve()`: aborts anything in flight, sets `capturing` (which hides the window), waits `capture.hideDelayMs`
  only if the window was visible (so it isn't in the screenshot), validates the provider, then captures.
  On capture -> `thinking` -> `provider.solve({prompt, systemPrompt, imageBase64, mimeType})`.
  On success -> `done` (+ auto copy if `window.copyAnswer`); on failure -> `error`.
  A cancelled `slurp` selection returns silently to `idle`.
- `toggle()`, `dismiss()`, `copy()` (wl-copy of answer, or of the error in error state).
- Stale results are ignored by checking the current state in signal handlers.

### Capture (`services/Capture.qml`)

- `capture({mode, format, quality, scale}): bool` (false if already busy), `cancel()`, `busy`, `focusedMonitor`.
- Signals: `captured({base64, mimeType, monitor})`, `failed(message)` (`"Selection cancelled"` for slurp cancel, exit 130).
- Runs an inline bash script (`set -o pipefail`; `grim [-t fmt] [-q q] [-s scale] [-o monitor | -g geom] - | base64 -w0`).
  `scale` is relative to the logical (scaled) size; `0` = grim default (full resolution).

### Providers (`services/providers/`)

`Provider.qml` contract:
- Properties: `key` (config id, e.g. `"openrouter"`), `displayName`, `model` (shown in UI), `busy`.
- `validate(): string` — `""` if ready, otherwise a user-facing message (e.g. missing API key).
- `solve(request)` — request `{ prompt, systemPrompt, imageBase64, mimeType }`; must emit exactly one of
  `succeeded(text)` / `failed(message)` unless `cancel()` is called first.
- `cancel()` — abort silently.

`OpenRouter.qml`: key from `openrouter.apiKey` or `$OPENROUTER_API_KEY`; sends system + user (text + image_url
data URI) messages, `max_tokens`, `temperature`, then shallow-merges `openrouter.extraBody`. Headers:
`Authorization`, `Content-Type`, `HTTP-Referer`, `X-Title: ScreenSolver`. Timeout via a Timer that aborts the XHR.
Handles array-form `content`, error bodies (`error.message`), 401 hint, empty responses.

**Adding a provider:** create `services/providers/Foo.qml` extending `Provider` (`key: "foo"`), add `Foo {}`
to `Providers.all`, add a `foo` `JsonObject` section in `Config.qml`, set `"provider": "foo"`, document it here.

### UI (`ui/AnswerWindow.qml`)

- `PanelWindow`, namespace `screensolver`, `WlrLayer.Overlay`, `WlrKeyboardFocus.OnDemand`, `ExclusionMode.Ignore`,
  shown on the screen matching `Solver.monitor`. Only instantiated while `Solver.visible` (LazyLoader).
- Positioned by `window.position` via anchors; size = `window.width` x min(content, `window.maxHeight`) (scrollable).
- Header: status dot (pulses while busy; green done, red error), title, model, elapsed time, copy/retry/close buttons
  (copy icon drawn with Rectangles, no icon-font dependency). Body: "Thinking..." animation, or the answer
  (selectable `TextEdit`, Markdown if `window.markdown`) / error text.
- Auto-hide after `window.autoHideMs` when done, paused while hovered.
- Local inline components: `Label` (themed Text), `IconButton`.

## Configuration

File: `~/.config/screensolver/config.json` (`$XDG_CONFIG_HOME` respected). Directory created `700`, file
`600` on creation (holds the API key). Auto-created with defaults on first run, watched and hot-reloaded;
missing keys fall back to defaults.

| key | default | notes |
|-----|---------|-------|
| `provider` | `"openrouter"` | provider key from the registry |
| `prompt.system` | concise solver instructions | system message |
| `prompt.user` | `"Solve whatever is on the screen, and provide the most concise answer possible."` | user text sent with the image |
| `capture.mode` | `"focused"` | `focused` / `all` / `region` (slurp) |
| `capture.format` | `"png"` | `png` / `jpeg` |
| `capture.jpegQuality` | `85` | |
| `capture.scale` | `0` | grim `-s`; 0 = default |
| `capture.hideDelayMs` | `250` | delay before capturing when the window was visible |
| `openrouter.apiKey` | `""` | fallback `$OPENROUTER_API_KEY` |
| `openrouter.model` | `"google/gemini-3.8-flash"` | any vision-capable OpenRouter model |
| `openrouter.endpoint` | `"https://openrouter.ai/api/v1/chat/completions"` | |
| `openrouter.maxTokens` | `1024` | omitted if <= 0 |
| `openrouter.temperature` | `0.2` | omitted if < 0 |
| `openrouter.timeoutMs` | `90000` | |
| `openrouter.extraBody` | `{}` | merged into request body, e.g. `{"reasoning": {"effort": "low"}}` |
| `window.position` | `"top-right"` | `top-left`, `top`, `top-right`, `bottom-left`, `bottom`, `bottom-right`, `center` |
| `window.width` / `maxHeight` / `margin` | `420` / `520` / `18` | px |
| `window.autoHideMs` | `0` | 0 = never |
| `window.copyAnswer` | `false` | auto-copy answers |
| `window.markdown` | `true` | render Markdown |
| `theme.background/surface/foreground/muted/accent/error/border` | dark palette | `#RRGGBB` or `#AARRGGBB` |
| `theme.radius` / `fontFamily` / `fontSize` | `14` / `""` (system) / `14` | |

**Adding an option:** add a property to the relevant `JsonObject` in `config/Config.qml`, read it via
`Config.options.<section>.<key>`, and add it to the table above (and README).

## Conventions

- QML style: `pragma ComponentBehavior: Bound`, `id: root` at top level, reference members via `root.`.
- No property may be named `id` (QML reserved) — providers use `key`.
- Keep secrets out of process arguments (use XHR / env, not curl argv).
- Verify changes by running `qs -p .` and checking logs; test IPC with `bin/screensolver status`.
  A local mock HTTP server + temporary `openrouter.endpoint` override is a convenient way to test the success path.

## Status / roadmap

- Implemented: keybind-triggered capture -> OpenRouter -> overlay answer; JSON config with hot reload.
- Future (planned): much richer configuration (likely a settings UI), more providers.
