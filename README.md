# ScreenSolver

A tiny [Quickshell](https://quickshell.org) app: press a key → it screenshots your
screen → sends it to an AI model → shows the most concise answer in a small overlay.

## Requirements

`quickshell` (0.2+), `grim`, `bash`, `base64` (coreutils), `wl-copy` (copy), `slurp` (only for `region` mode). Hyprland (used to detect the focused monitor).

Optional, for LaTeX math: [MicroTeX](https://github.com/NanoMichael/MicroTeX) at `/opt/MicroTeX/LaTeX` (AUR
`illogical-impulse-microtex-git`) and `python3` (md4c from qt6-base is used for Markdown → HTML). Without it,
answers just show as Markdown.

## Setup

1. Start it once (creates `~/.config/screensolver/config.json`):

   ```sh
   ./bin/screensolver status
   ```

2. Add your OpenRouter key: press the key, hover the dot, click ⚙ → General → API key
   (or edit `~/.config/screensolver/config.json` → `openrouter.apiKey`, or export `OPENROUTER_API_KEY`).
   The file is hot-reloaded, no restart needed.

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
| `toggle`  | (default) idle → hub dot, hub → solve, showing → close |
| `solve`   | screenshot + solve right away                     |
| `hub`     | show the hub dot                                  |
| `settings`| open the settings card                            |
| `dismiss` | close the window / cancel the request             |
| `copy`    | copy the answer to the clipboard                  |
| `status`  | `idle` / `hub` / `settings` / `capturing` / `thinking` / `done` / `error` |
| `answer`  | print the last answer                             |

**One key flow:** press once → a still black dot (the *hub*) appears in the corner for 5s
(`window.hubTimeoutMs`, paused while hovered). Hover it for two buttons: ▶ solve and ⚙ settings.
Press the key again (or click ▶) to solve: the dot stays put, gives one strong pulse, then keeps pulsing while thinking; it grows into the answer card
when done, with round copy / retry / close buttons beside it. Pressing the key while anything is showing closes it.

**Settings (⚙):** the dot grows into a settings card; the round buttons beside it are tabs —
⌂ General (API key, endpoint, capture mode, auto-copy, timeouts), ≡ Models (comes preloaded with Gemini, Claude, GPT,
GLM 5.3 Flash, Hy4 and Kimi K3.1 Pro; add any other model id, click one to make it active, ✕ to remove,
"Restore built-in models" brings removed presets back), ◐ Appearance (corner position, background / foreground / accent colors (presets or any hex), corner roundness, width, max height, margin, font
size, Markdown, LaTeX math, font picker) — and ✕ closes. Changes apply live and are saved to the config file.

**Math:** the model is told to write inline math as `$...$` and display math as `$$...$$` (with `aligned`,
`cases`, matrices, `\boxed{}` …); formulas are rendered as crisp SVGs right in the answer text. Copy still
gives you the raw LaTeX/Markdown.

The window never takes keyboard focus, so your typing always stays in the app you're using — except the
settings card, which takes focus only when you click into it (for the text fields; Esc closes it). Copy grabs
your text selection if you made one, otherwise the whole answer.

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
| `openrouter.model` | `"google/gemini-3.8-flash"` | active model; any vision-capable OpenRouter model |
| `openrouter.models` | built-in catalog (`config/Models.qml`) | models listed in Settings → Models |
| `openrouter.maxTokens` / `temperature` / `timeoutMs` | `1024` / `0.2` / `90000` | |
| `openrouter.extraBody` | `{}` | merged into the request body, e.g. `{"reasoning": {"effort": "low"}}` |
| `window.position` | `"top-right"` | `top-left`, `top`, `top-right`, `bottom-*`, `center` |
| `window.width` / `maxHeight` / `margin` | `420` / `520` / `18` | |
| `window.autoHideMs` | `0` | auto-dismiss after an answer (0 = never; paused while hovered) |
| `window.hubTimeoutMs` | `5000` | how long the hub dot stays (0 = until dismissed; paused while hovered) |
| `window.copyAnswer` | `false` | copy the answer automatically |
| `window.markdown` | `true` | render answers as Markdown |
| `latex.enabled` | `true` | render LaTeX math (needs `window.markdown`) and tell the model how to write it |
| `latex.binary` / `scale` / `timeoutMs` | `/opt/MicroTeX/LaTeX` / `1.1` / `6000` | MicroTeX CLI, formula size vs text, render timeout |
| `theme.*` | dark | colors (`#AARRGGBB` ok), `radius`, `fontFamily`, `fontSize` |

## Architecture

```
shell.qml                     entry: IPC handler + lazily-loaded window
bin/screensolver              launcher / IPC trigger for keybinds
bin/screensolver-latex        Markdown + LaTeX → rich text with cached SVG formulas
config/
  Paths.qml                   all filesystem locations
  Config.qml                  JSON config (defaults, hot reload, auto-create)
services/
  Solver.qml                  pipeline + state machine (capture → provider → answer)
  Capture.qml                 grim/slurp screenshot → base64
  Latex.qml                   LaTeX prompt guide + renderer runner
  providers/
    Provider.qml              provider interface (solve / cancel / validate)
    OpenRouter.qml            OpenRouter implementation
    Providers.qml             provider registry
ui/
  AnswerWindow.qml            the overlay (hub dot / thinking dot / answer card / settings card)
  SettingsView.qml            settings tabs content
  widgets/                    Field, Stepper, Toggle, Segmented, SectionLabel, ColorField
```

The UI only observes `Solver`; `Solver` only talks to `Capture` and the
`Provider` interface; every tunable lives in `Config`.

**Adding a provider:** create `services/providers/Foo.qml` extending `Provider`
(set `key: "foo"`, implement `solve(request)` emitting `succeeded(text)` /
`failed(message)`), add `Foo {}` to `Providers.all`, add a `foo` `JsonObject`
to `Config.qml`, then set `"provider": "foo"`.

**Adding an option:** add a property to the relevant `JsonObject` in
`config/Config.qml` and read it via `Config.options.<section>.<name>`.
