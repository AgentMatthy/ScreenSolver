#!/usr/bin/env bash
# ScreenSolver installer.
#
#   curl -fsSL https://raw.githubusercontent.com/AgentMatthy/ScreenSolver/main/install.sh | bash
#
# Downloads (or updates) ScreenSolver, puts the `screensolver` command on your PATH,
# checks what's missing on your system, asks for your OpenRouter API key and helps
# you set up a keybind. Safe to run again any time (that's also how you update).
#
# Environment overrides:
#   SCREENSOLVER_DIR   where to install       (default ~/.local/share/screensolver)
#   SCREENSOLVER_BIN   where to put the command (default ~/.local/bin)
#   SCREENSOLVER_REPO  git repo to install from
set -euo pipefail

REPO="${SCREENSOLVER_REPO:-https://github.com/AgentMatthy/ScreenSolver.git}"
DIR="${SCREENSOLVER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/screensolver}"
BIN_DIR="${SCREENSOLVER_BIN:-$HOME/.local/bin}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/screensolver"
CONFIG_FILE="$CONFIG_DIR/config.json"
MICROTEX="/opt/MicroTeX/LaTeX"

# ── pretty output ────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    B=$'\e[1m' D=$'\e[2m' R=$'\e[0m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m'
else
    B='' D='' R='' RED='' GRN='' YLW='' BLU=''
fi
step() { printf '\n%s==>%s %s%s%s\n' "$BLU" "$R" "$B" "$*" "$R"; }
ok()   { printf '  %s✓%s %s\n' "$GRN" "$R" "$*"; }
warn() { printf '  %s!%s %s\n' "$YLW" "$R" "$*"; }
bad()  { printf '  %s✗%s %s\n' "$RED" "$R" "$*"; }
info() { printf '    %s%s%s\n' "$D" "$*" "$R"; }
die()  { printf '\n%serror:%s %s\n' "$RED" "$R" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# The script is usually piped into bash, so questions are read from the terminal.
TTY=""
if [ -r /dev/tty ] && { : </dev/tty; } 2>/dev/null; then TTY=/dev/tty; fi

# ask "question" default(y|n) -> returns 0 for yes
ask() {
    local prompt="$1" def="${2:-y}" hint reply
    [ "$def" = y ] && hint="[Y/n]" || hint="[y/N]"
    if [ -z "$TTY" ]; then [ "$def" = y ]; return; fi
    printf '  %s?%s %s %s ' "$BLU" "$R" "$prompt" "$hint" >"$TTY"
    read -r reply <"$TTY" || reply=""
    reply="${reply:-$def}"
    [[ "$reply" =~ ^[Yy] ]]
}

printf '%s\n' "${B}ScreenSolver installer${R}"
printf '%s\n' "${D}Press a key, get the answer to whatever is on your screen.${R}"

# ── 1. download ──────────────────────────────────────────────────────────────
step "Downloading ScreenSolver"
have git || die "git is needed to download ScreenSolver. Install it first:  sudo pacman -S git"

if [ -d "$DIR/.git" ]; then
    info "Already installed in $DIR — updating"
    if git -C "$DIR" pull --ff-only --quiet; then
        ok "Updated to the latest version"
    else
        warn "Couldn't update automatically (local changes?). Keeping the current version."
    fi
elif [ -e "$DIR" ] && [ -n "$(ls -A "$DIR" 2>/dev/null)" ]; then
    die "$DIR already exists and isn't a ScreenSolver install. Move it away or set SCREENSOLVER_DIR."
else
    mkdir -p "$(dirname "$DIR")"
    git clone --quiet --depth 1 "$REPO" "$DIR" || die "Download failed. Check your internet connection."
    ok "Installed to $DIR"
fi
chmod +x "$DIR/bin/screensolver" "$DIR/bin/screensolver-latex" 2>/dev/null || true

# ── 2. the `screensolver` command ────────────────────────────────────────────
step "Adding the screensolver command"
mkdir -p "$BIN_DIR"
ln -sfn "$DIR/bin/screensolver" "$BIN_DIR/screensolver"
ok "screensolver → $BIN_DIR/screensolver"
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not on your PATH."
       info "Add this to your shell config (~/.bashrc, ~/.zshrc, …):"
       info "  export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac
CMD="$BIN_DIR/screensolver"

# ── 3. requirements ──────────────────────────────────────────────────────────
step "Checking requirements"
missing_pkgs=()   # official Arch packages
missing_aur=()    # AUR packages

# command  arch-package  description
need() {
    if have "$1"; then
        ok "$3"
    else
        bad "$3 ${D}(missing: $1)${R}"
        missing_pkgs+=("$2")
    fi
}
need qs      quickshell   "Quickshell — draws the overlay"
need grim    grim         "grim — takes the screenshot"
need slurp   slurp        "slurp — lets you pick a screen region"
need wl-copy wl-clipboard "wl-clipboard — copies answers"
need base64  coreutils    "coreutils"

# Optional: pretty math formulas.
math_ok=1
if have python3; then
    ok "Python 3 ${D}(for math formulas)${R}"
else
    warn "Python 3 not found ${D}(optional — needed for math formulas)${R}"
    missing_pkgs+=(python); math_ok=0
fi
if [ -x "$MICROTEX" ]; then
    ok "MicroTeX ${D}(for math formulas)${R}"
else
    warn "MicroTeX not found ${D}(optional — math is shown as plain text without it)${R}"
    missing_aur+=(illogical-impulse-microtex-git); math_ok=0
fi

# Desktop session.
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    ok "Hyprland detected"
    HYPR=1
else
    HYPR=0
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        warn "You're not on Hyprland. ScreenSolver should still work on most Wayland"
        info "compositors (Sway, niri, river, …), but Hyprland is what it's tested on."
    else
        warn "No Wayland session detected. ScreenSolver needs a Wayland desktop"
        info "(Hyprland recommended). You can finish installing and use it there later."
    fi
fi

if [ ${#missing_pkgs[@]} -gt 0 ] || [ ${#missing_aur[@]} -gt 0 ]; then
    printf '\n  %sSome things are missing.%s On Arch Linux, install them with:\n\n' "$B" "$R"
    [ ${#missing_pkgs[@]} -gt 0 ] && printf '    %ssudo pacman -S --needed %s%s\n' "$B" "${missing_pkgs[*]}" "$R"
    [ ${#missing_aur[@]} -gt 0 ] && printf '    %syay -S %s%s   %s(AUR, optional)%s\n' "$B" "${missing_aur[*]}" "$R" "$D" "$R"
    printf '\n    %sOther distros: install the same tools with your package manager.%s\n' "$D" "$R"

    if [ ${#missing_pkgs[@]} -gt 0 ] && have pacman && [ -n "$TTY" ]; then
        if ask "Run the pacman command now?" n; then
            sudo pacman -S --needed "${missing_pkgs[@]}" <"$TTY" || warn "pacman didn't finish — install them manually later."
        fi
    fi
else
    ok "Everything is installed"
fi

# ── 4. OpenRouter API key ────────────────────────────────────────────────────
step "OpenRouter API key"
info "ScreenSolver uses OpenRouter to talk to AI models."
info "Get a key at ${B}https://openrouter.ai/keys${R}${D} (it looks like sk-or-…)."

json_get_key() {
    [ -f "$CONFIG_FILE" ] || return 0
    if have python3; then
        python3 - "$CONFIG_FILE" <<'PY' 2>/dev/null || true
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("openrouter", {}).get("apiKey", ""))
except Exception:
    pass
PY
    else
        sed -n 's/.*"apiKey"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG_FILE" | head -n1
    fi
}

# Saves the key into the config file, keeping every other setting.
save_key() {
    local key="$1"
    mkdir -p "$CONFIG_DIR" && chmod 700 "$CONFIG_DIR"
    if have python3; then
        SS_KEY="$key" python3 - "$CONFIG_FILE" <<'PY'
import json, os, sys
path = sys.argv[1]
try:
    cfg = json.load(open(path))
except Exception:
    cfg = {}
cfg.setdefault("openrouter", {})["apiKey"] = os.environ["SS_KEY"]
tmp = path + ".tmp"
with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
    json.dump(cfg, f, indent=4)
os.replace(tmp, path)
PY
    elif [ ! -s "$CONFIG_FILE" ]; then
        local esc="${key//\\/\\\\}"; esc="${esc//\"/\\\"}"
        (umask 077; printf '{\n    "openrouter": {\n        "apiKey": "%s"\n    }\n}\n' "$esc" >"$CONFIG_FILE")
    else
        return 1
    fi
    chmod 600 "$CONFIG_FILE"
}

# Checks the key with OpenRouter (key goes through stdin, not the command line).
check_key() {
    have curl || return 2
    printf 'Authorization: Bearer %s\n' "$1" |
        curl -fsS -o /dev/null --max-time 10 -H @- https://openrouter.ai/api/v1/key 2>/dev/null
}

existing="$(json_get_key)"
key=""
if [ -n "$existing" ]; then
    ok "A key is already saved (${existing:0:8}…)"
    ask "Keep it?" y || existing=""
fi
if [ -z "$existing" ]; then
    if [ -n "$TTY" ]; then
        printf '  %s?%s Paste your key (input hidden, Enter to skip): ' "$BLU" "$R" >"$TTY"
        read -rs key <"$TTY" || key=""
        printf '\n' >"$TTY"
        key="$(printf '%s' "$key" | tr -d '[:space:]')"
    fi
    if [ -z "$key" ] && [ -n "${OPENROUTER_API_KEY:-}" ]; then
        key="$OPENROUTER_API_KEY"; info "Using \$OPENROUTER_API_KEY from your environment"
    fi
    if [ -z "$key" ]; then
        warn "Skipped. You can add it later in ScreenSolver's settings (⚙ → General)."
    else
        if check_key "$key"; then
            ok "Key works"
        else
            case $? in
                2) ;;
                *) warn "OpenRouter didn't accept that key (or couldn't be reached). Saving it anyway —" 
                   info "you can change it later in ScreenSolver's settings." ;;
            esac
        fi
        if save_key "$key"; then
            ok "Saved to $CONFIG_FILE"
        else
            warn "Couldn't save the key automatically — add it in ScreenSolver's settings (⚙ → General)."
        fi
    fi
fi

# ── 5. keybind ───────────────────────────────────────────────────────────────
step "Keybind"
HYPR_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.conf"
hypr_lines="exec-once = $CMD daemon
bind = SUPER SHIFT, S, exec, $CMD"

if [ "$HYPR" = 1 ] || [ -f "$HYPR_CONF" ]; then
    if [ -f "$HYPR_CONF" ] && grep -q "screensolver" "$HYPR_CONF" 2>/dev/null; then
        ok "Your Hyprland config already mentions screensolver — leaving it alone"
    elif [ -f "$HYPR_CONF" ] && ask "Add a ${B}Super + Shift + S${R} keybind to your Hyprland config?" y; then
        printf '\n# ScreenSolver\n%s\n' "$hypr_lines" >>"$HYPR_CONF"
        ok "Added to $HYPR_CONF"
        info "Already using Super + Shift + S for something else? Change the key in that file."
    else
        info "Add these lines to your Hyprland config:"
        printf '%s\n' "$hypr_lines" | sed "s/^/      ${B}/; s/\$/${R}/"
    fi
else
    info "Bind this command to a key in your window manager / desktop settings:"
    printf '      %s%s%s\n' "$B" "$CMD" "$R"
    info "and (optional, makes the first press instant) run this on login:"
    printf '      %s%s daemon%s\n' "$B" "$CMD" "$R"
fi

# ── 6. warm up ───────────────────────────────────────────────────────────────
if have qs && [ -n "${WAYLAND_DISPLAY:-}" ]; then
    "$CMD" status >/dev/null 2>&1 && ok "ScreenSolver is running in the background" || true
fi

# ── done ─────────────────────────────────────────────────────────────────────
printf '\n%s%sAll done!%s\n' "$GRN" "$B" "$R"
if [ ${#missing_pkgs[@]} -gt 0 ]; then
    for c in qs grim wl-copy; do
        have "$c" || { printf '%sDon'"'"'t forget to install the missing packages above.%s\n' "$YLW" "$R"; break; }
    done
fi
[ "$math_ok" = 0 ] && printf '%sMath formulas will show as plain text until the optional extras are installed.%s\n' "$D" "$R"
cat <<EOF

  Press your key once  → a small dot appears
  Press it again       → it reads your screen and shows the answer
  Hover the dot → ⚙    → settings (API key, models, look & feel)

  Update any time by running the install command again.
EOF
