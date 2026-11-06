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
- Trigger: `bin/screensolver [toggle|solve|hub|settings|dismiss|copy|status|answer]` (default `toggle`).
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
- IPC target `solver` (in `shell.qml`): `toggle()`, `solve()`, `hub()`, `settings()`, `dismiss()`, `copy()`,
  `status(): string`, `answer(): string`, `configPath(): string`.
- **One-key flow** (`toggle`, the default command, bound to SUPER+X here): idle → **hub** (still dot, shown
  `window.hubTimeoutMs` = 5s, timer paused while hovered; hovering pops out ▶ solve and ⚙ settings buttons) →
  press again / click ▶ → solve → answer. Pressing while anything else is showing dismisses.
- The window **never takes keyboard focus** (not on map, not on click), so there are no in-window key shortcuts;
  use global binds to the IPC commands (`dismiss`, `solve`, `copy`) instead. Buttons: copy (copies the
  mouse selection if any, else the whole answer), retry, close. **Exception: settings mode** switches the
  layer to `WlrKeyboardFocus.OnDemand` (focus only when clicked, needed for text fields; Esc then closes).

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
  AnswerWindow.qml            PanelWindow overlay (wlr-layer-shell, Overlay layer): hub / thinking / answer / settings
  SettingsView.qml            settings content (tabs General / Models / Appearance), writes Config.options directly
  widgets/                    reusable controls (import qs.ui.widgets), all themed from Config.options.theme:
    Field.qml                 text field (value/committed on Enter-blur-destruction, accepted, secret + show/hide)
    Stepper.qml               label + − value + (click, hold to repeat, wheel); signal moved(value)
    Toggle.qml                label + switch; signal toggled(checked)
    Segmented.qml             pill choice; options strings or {label,value}; signal picked(value)
    SectionLabel.qml          small uppercase muted heading
    ColorField.qml            label + swatch + hex field (#rgb/#rrggbb/#aarrggbb, invalid → red border, reverts);
                              swatch toggles an inline preset row; signal picked(color)
```

Imports use Quickshell's root module system: `import qs.config`, `import qs.services`,
`import qs.services.providers`, `import qs.ui`. Singletons use `pragma Singleton` + `Singleton {}`.

Data flow / responsibilities:
- **UI only observes `Solver`** (state, answer, error, monitor, timings) and calls its functions.
- **`Solver` only talks to `Capture` and the `Provider` interface**, reading settings from `Config`.
- **Every tunable lives in `Config.qml`.**

### Solver (`services/Solver.qml`)

- `state`: `"idle" | "hub" | "settings" | "capturing" | "thinking" | "done" | "error"` (string, also returned over IPC).
- Properties: `answer`, `error`, `monitor` (monitor name the window shows on), `startedAt`, `finishedAt`,
  `provider` (= `Providers.get(Config.options.provider)`), `visible` (hub/settings/thinking/done/error), `busy` (capturing/thinking).
- `hub()`: abort, clear, monitor = focused monitor, state `hub`. `settings()`: abort, state `settings`
  (takes the focused monitor only if nothing was showing).
- `solve()`: aborts anything in flight, sets `capturing` (which hides the window), waits `capture.hideDelayMs`
  only if the window was visible (so it isn't in the screenshot), validates the provider, then captures.
  On capture -> `thinking` -> `provider.solve({prompt, systemPrompt, imageBase64, mimeType})`.
  On success -> `done` (+ auto copy if `window.copyAnswer`); on failure -> `error`.
  A cancelled `slurp` selection returns silently to `idle`.
- `toggle()`: idle → `hub()`, hub → `solve()`, capturing → no-op, else → `dismiss()`. `dismiss()`, `copy()` (wl-copy of answer, or of the error in error state).
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

- `PanelWindow`, namespace `screensolver`, `WlrLayer.Overlay`, `WlrKeyboardFocus.None` + `focusable: false` (must never steal
  focus — Hyprland focuses OnDemand layers on map; the `TextEdit` also has `activeFocusOnPress: false`), `ExclusionMode.Ignore`,
  shown on the screen matching `Solver.monitor`. Only instantiated while `Solver.visible` (LazyLoader).
- Positioned by `window.position` via anchors. The surface has a fixed size (`window.width` + gap + button size)
  x max(`window.maxHeight`, button column) so the morph never resizes it; an input `mask` (Region: card + buttons)
  keeps the transparent rest click-through.
- Minimal look, no header/title/model/status/elapsed time, no border, pure black (`theme.background` `#000000`):
  - `thinking`: only a small black dot (14px) in the anchored corner, pulsing by scale (1 ↔ 0.7, never fades).
  - `done`/`error`: the dot morphs (width/height/radius, 320ms OutCubic) into the answer card (selectable
    `TextEdit`, Markdown if `window.markdown`, scrollable; error text in `theme.error`). Content is fixed-size,
    pinned to the anchored corner and revealed as the card grows.
  - Buttons copy/retry/close are separate round black dots (30px) in a column beside the card — on its left,
    or on its right when `position` ends in `left` — popping in with the morph. Copy icon is drawn with
    Rectangles (no icon font) and shows ✓ for 1s after copying.
  - `hub`: the same 14px dot, still, centred in a 30px "slot" in the corner (so it lines up with the buttons;
    `card.inset` animates to 0 when expanding). Hovering pops out a column: ▶ `Solver.solve()`, ⚙ `Solver.settings()`.
    The mask uses `hubZone` (slot + gap + button column while open) so hover holds when crossing the gap.
    Dismissed by the hub Timer after `window.hubTimeoutMs` unless hovered.
  - `settings`: the dot morphs into a card of height min(`window.maxHeight`, 460) hosting `SettingsView`
    (Loader). The button column beside it is tabs ⌂ General / ≡ Models / ◐ Appearance (active tab lit with
    `theme.surface`) + ✕ close. Content: General = API key (secret field), endpoint, capture mode, auto-copy,
    hub timeout, auto-hide; Models = `openrouter.models` list ∪ active model, click = set `openrouter.model`,
    hover ✕ removes (removing the active one activates the first left), add field (Enter or +);
    Appearance = 4-corner position picker, Colors (ColorFields for `theme.background/foreground/accent`
    with presets; changing background/foreground re-derives `theme.surface` = tint(bg, fg@11%) and
    `theme.muted` = tint(bg, fg@55%) so controls stay visible; "reset" link restores the default palette
    incl. surface/muted), steppers for `theme.radius`, `window.width/maxHeight/margin`,
    `theme.fontSize`, Markdown toggle, searchable font list (`Qt.fontFamilies()`, each rendered in itself).
    Everything applies live (Config writes the JSON; hot reload).
- `mode` = `dot` (hub/thinking) | `answer` | `settings`; `activeButtons` = the shown ButtonColumn (or null), used in the mask.
- Auto-hide after `window.autoHideMs` when done, paused while hovered.
- Local inline components: `ButtonColumn` (positioned beside card/slot), `IconButton` (round black button;
  `shown` drives pop-in, `active` = lit tab, `glyphSize`).

## Configuration

File: `~/.config/screensolver/config.json` (`$XDG_CONFIG_HOME` respected). Directory created `700`, file
`600` on creation and re-`chmod 600`'d after every save (`FileView.onSaved`; writes replace the file) since it holds the API key. Auto-created with defaults on first run, watched and hot-reloaded;
missing keys fall back to defaults. In-app edits are debounced (`saveTimer`, 80 ms) into one write, and
file-watch reloads are skipped while a write is pending or within 400 ms after our own save (`echoTimer`),
so a reload of an intermediate file can't clobber newer in-memory edits.

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
| `openrouter.model` | `"google/gemini-3.8-flash"` | active model; any vision-capable OpenRouter model |
| `openrouter.models` | `["google/gemini-3.8-flash"]` | list shown in Settings → Models (active one always shown too) |
| `openrouter.endpoint` | `"https://openrouter.ai/api/v1/chat/completions"` | |
| `openrouter.maxTokens` | `1024` | omitted if <= 0 |
| `openrouter.temperature` | `0.2` | omitted if < 0 |
| `openrouter.timeoutMs` | `90000` | |
| `openrouter.extraBody` | `{}` | merged into request body, e.g. `{"reasoning": {"effort": "low"}}` |
| `window.position` | `"top-right"` | `top-left`, `top`, `top-right`, `bottom-left`, `bottom`, `bottom-right`, `center` |
| `window.width` / `maxHeight` / `margin` | `420` / `520` / `18` | px |
| `window.autoHideMs` | `0` | 0 = never |
| `window.hubTimeoutMs` | `5000` | hub dot lifetime when not hovered; 0 = until dismissed |
| `window.copyAnswer` | `false` | auto-copy answers |
| `window.markdown` | `true` | render Markdown |
| `theme.background/surface/foreground/muted/accent/error` | black bg (`#000000`), dark palette | `#RRGGBB` or `#AARRGGBB` |
| `theme.radius` / `fontFamily` / `fontSize` | `14` / `""` (system) / `14` | |

**Adding an option:** add a property to the relevant `JsonObject` in `config/Config.qml`, read it via
`Config.options.<section>.<key>`, and add it to the table above (and README).

## Conventions

- QML style: `pragma ComponentBehavior: Bound`, `id: root` at top level, reference members via `root.`.
- No property may be named `id` (QML reserved) — providers use `key`.
- Keep secrets out of process arguments (use XHR / env, not curl argv).
- Verify changes by running `qs -p .` and checking logs; test IPC with `bin/screensolver status`.
  A local mock HTTP server + temporary `openrouter.endpoint` override is a convenient way to test the success path.
  UI testing on this Hyprland (Lua config): move the pointer with `hyprctl dispatch "hl.dsp.cursor.move({x=X,y=Y})"`
  followed by `wlrctl pointer move 1 0` (to emit motion), click with `wlrctl pointer click left`, type with `wtype`,
  screenshot with `grim -g`; temporarily set `theme.background` to a bright color to see the black shapes.

## Status / roadmap

- Implemented: keybind-triggered capture -> OpenRouter -> overlay answer; JSON config with hot reload.
- Implemented: hub launcher dot + in-overlay settings UI (API key, models, appearance).
- Future (planned): more settings (prompts, colors), more providers.
