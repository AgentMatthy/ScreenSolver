# ScreenSolver

**Press a key. Get the answer.**

ScreenSolver looks at whatever is on your screen (a math problem, a quiz question, an error
message, a confusing chart) and shows the answer in a small, clean card in the corner. You get the
answer first, then a short explanation of how to get there.

It stays out of your way. No windows to manage and no copy-pasting into a chat, and it never steals
your keyboard focus.

---

## Install

Open a terminal and paste:

```sh
curl -fsSL https://raw.githubusercontent.com/AgentMatthy/ScreenSolver/main/install.sh | bash
```

The installer will:

- download ScreenSolver and add a `screensolver` command
- check that everything it needs is on your system, and tell you exactly what to install if not
- ask for your **OpenRouter API key** (see below)
- offer to set up a keyboard shortcut for you on Hyprland

Running the same command again later **updates** ScreenSolver.

### What you need

- **A Wayland desktop.** Works best on **Hyprland**. Other Wayland compositors like Sway, niri or
  river should also work.
- **An OpenRouter account.** ScreenSolver uses [OpenRouter](https://openrouter.ai) to reach AI
  models like Gemini, Claude and GPT. Create a key at
  **[openrouter.ai/keys](https://openrouter.ai/keys)**. You pay OpenRouter per answer, and on most
  models that's very little.
- **A few small programs.** If any are missing, the installer lists them. On Arch Linux:

  ```sh
  sudo pacman -S --needed quickshell grim slurp wl-clipboard python
  ```

  For nicely rendered math formulas (optional), also install from the AUR:

  ```sh
  yay -S illogical-impulse-microtex-git
  ```

  On other distros, install the same programs with your package manager.

---

## How to use it

1. **Press your shortcut** (the installer suggests <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>S</kbd>).
   A small black dot appears in the corner.
2. **Press it again** (or click ▶ on the dot). The dot pulses while it thinks, then grows into the
   answer.
3. **Done?** Press the shortcut once more, or click ✕.

Next to the answer you'll find buttons to **copy** it, **retry**, or **close** it. If you select part
of the answer first, copy grabs just that part.

> **Tip:** the dot disappears by itself after a few seconds if you don't use it.

---

## Settings

Hover the dot and click **⚙**. Everything changes instantly, nothing needs a restart.

- **⌂ General**: your API key, what to capture (current screen, all screens, or a region you drag
  out), auto-copy answers, timers
- **≡ Models**: pick which AI answers you. Gemini, Claude, GPT and more come built in, and you can
  add any vision model from OpenRouter
- **◐ Appearance**: which corner it sits in (and fine-tune its position pixel by pixel), colors,
  roundness, size, font, and math rendering

---

## Setting up the shortcut yourself

If you skipped it during install, or you don't use Hyprland:

**Hyprland**: add to `~/.config/hypr/hyprland.conf`:

```ini
exec-once = ~/.local/bin/screensolver daemon
bind = SUPER SHIFT, S, exec, ~/.local/bin/screensolver
```

**Anything else**: in your desktop or window manager's keyboard settings, bind a key to:

```sh
~/.local/bin/screensolver
```

To make the very first press faster, you can also run `screensolver daemon` when you log in.

---

## Troubleshooting

- **"No OpenRouter API key set"**: open ⚙ → General and paste your key.
- **Nothing happens when I press the key**: run `screensolver` in a terminal and see what it says.
  Usually a program is missing. Run the install command again and it will tell you which one.
- **Math looks like `$x^2$` instead of a formula**: install the optional math extras listed above.
- **Wrong or weak answers**: try a different model in ⚙ → Models.

---

## Uninstall

```sh
rm -rf ~/.local/share/screensolver ~/.local/bin/screensolver
rm -rf ~/.config/screensolver   # your settings and API key
```

Then remove the shortcut lines from your desktop's config.

---

<sub>Curious how it works inside? See [DESCRIPTION.md](DESCRIPTION.md).</sub>
