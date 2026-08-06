#!/usr/bin/env bash
# claude-macho-fix — one-click repair script
#
# Fixes two independent issues that can occur after patching Claude Desktop
# on macOS. Safe to run multiple times. Does NOT re-run whatever patch broke
# the app — it only repairs whatever Claude.app you currently have.
#
#  1. "Claude Code process exited with code 127 — Malformed Mach-o file"
#     (stale/inconsistent nested code signatures)
#  2. "[FATAL] Integrity check failed for asar archive (X vs Y)" — the whole
#     app fails to launch (Electron's embedded ASAR integrity fuse)
#
# See README.md for the full explanation of both. Run with no arguments and
# it will find Claude.app on its own, walk you through each step, and tell
# you exactly what to do next — no flags or prior knowledge required.

set -uo pipefail

# ---------------------------------------------------------------------------
# Pretty output (falls back to plain text if the terminal has no color)
# ---------------------------------------------------------------------------
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    BOLD="$(tput bold)"; DIM="$(tput dim)"; RESET="$(tput sgr0)"
    RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"; BLUE="$(tput setaf 4)"
else
    BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; YELLOW=""; BLUE=""
fi

info()  { printf '%s\n' "${BLUE}[*]${RESET} $*"; }
ok()    { printf '%s\n' "${GREEN}[✓]${RESET} $*"; }
warn()  { printf '%s\n' "${YELLOW}[!]${RESET} $*"; }
fail()  { printf '%s\n' "${RED}[✗]${RESET} $*"; }
step()  { printf '\n%s\n' "${BOLD}==> $*${RESET}"; }

# ---------------------------------------------------------------------------
# 0. Figure out which Claude.app to repair
# ---------------------------------------------------------------------------
APP_PATH="${1:-}"

if [ -z "$APP_PATH" ]; then
    CANDIDATES=(
        "/Applications/Claude.app"
        "/Applications/Claude Beta.app"
        "$HOME/Applications/Claude.app"
        "$HOME/Applications/Claude Beta.app"
    )
    for candidate in "${CANDIDATES[@]}"; do
        if [ -d "$candidate" ]; then
            APP_PATH="$candidate"
            break
        fi
    done
fi

if [ -z "$APP_PATH" ]; then
    fail "Could not find Claude.app in any of the usual locations."
    echo "    Checked: /Applications, ~/Applications (Claude.app and Claude Beta.app)"
    echo ""
    echo "    If it's installed somewhere else, run this script again with the path:"
    echo "      ${BOLD}./repair.sh \"/path/to/Claude.app\"${RESET}"
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    fail "\"$APP_PATH\" not found."
    echo "    Usage: ./repair.sh [path-to-Claude.app]"
    exit 1
fi

APP_NAME="$(basename "$APP_PATH" .app)"

printf '\n%s\n' "${BOLD}Claude Desktop repair — Mach-O / ASAR integrity fix${RESET}"
info "Target: $APP_PATH"

# ---------------------------------------------------------------------------
# 1. Make sure the tools we need actually exist before touching anything
# ---------------------------------------------------------------------------
step "Checking prerequisites"

if ! command -v codesign >/dev/null 2>&1; then
    fail "codesign not found. This script only works on macOS with Xcode Command Line Tools installed."
    echo "    Install them with: xcode-select --install"
    exit 1
fi
ok "codesign found"

if ! command -v npx >/dev/null 2>&1; then
    fail "npx not found. Node.js is required (npx ships with it)."
    echo "    Install Node.js from https://nodejs.org and re-run this script."
    exit 1
fi
ok "npx found"

# ---------------------------------------------------------------------------
# 2. Quit Claude if it's running — codesign/fuse changes on a running app
#    bundle can silently fail to take effect on next launch.
# ---------------------------------------------------------------------------
step "Making sure $APP_NAME is not running"

if pgrep -f "$APP_PATH/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
    warn "$APP_NAME is currently running — quitting it first."
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 10); do
        pgrep -f "$APP_PATH/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || break
        sleep 0.5
    done
    if pgrep -f "$APP_PATH/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
        warn "Still running — force quitting."
        pkill -f "$APP_PATH/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || true
        sleep 1
    fi
    ok "$APP_NAME closed"
else
    ok "Not running"
fi

# ---------------------------------------------------------------------------
# 3. Disable Electron's embedded ASAR integrity fuse
# ---------------------------------------------------------------------------
step "[1/5] Disabling Electron's embedded ASAR integrity fuse"

if npx --yes @electron/fuses write --app "$APP_PATH" EnableEmbeddedAsarIntegrityValidation=off; then
    ok "Fuse disabled"
else
    fail "Failed to flip the fuse — see error above."
    echo "    This usually means the app bundle is read-only or you don't have"
    echo "    write permission to it. Try: sudo ./repair.sh \"$APP_PATH\""
    exit 1
fi

# ---------------------------------------------------------------------------
# 4. Strip stale nested signatures, clear xattrs, re-sign, verify
# ---------------------------------------------------------------------------
step "[2/5] Removing all existing nested code signatures"
codesign --remove-signature --deep "$APP_PATH" >/dev/null 2>&1 || true
ok "Done (any messages above about missing signatures are expected)"

step "[3/5] Clearing extended attributes"
if xattr -cr "$APP_PATH"; then
    ok "Done"
else
    warn "xattr reported an issue — continuing anyway, this is rarely fatal."
fi

step "[4/5] Signing from scratch (ad-hoc, deep)"
if codesign --force --deep --sign - "$APP_PATH"; then
    ok "Signed"
else
    fail "Signing failed — see error above."
    echo "    If you see a permissions error, try: sudo ./repair.sh \"$APP_PATH\""
    exit 1
fi

step "[5/5] Verifying"
if codesign --verify --deep --strict --verbose=4 "$APP_PATH" 2>&1 | sed 's/^/    /'; then
    printf '\n%s\n' "${GREEN}${BOLD}Signature is valid.${RESET}"
    echo ""
    echo "Next steps:"
    echo "  1. Make sure $APP_NAME is fully quit (Cmd+Q, or check the Dock/menu bar)."
    echo "  2. Reopen it and test the Claude Code tab."
    echo ""
    read -r -p "Reopen $APP_NAME now? [Y/n] " REPLY_OPEN
    case "$REPLY_OPEN" in
        [nN]*) echo "    OK — open it manually whenever you're ready." ;;
        *)
            if open "$APP_PATH" >/dev/null 2>&1; then
                ok "Launched $APP_NAME"
            else
                warn "Couldn't launch it automatically — open it from Finder or Spotlight."
            fi
            ;;
    esac
    echo ""
    echo "If it still misbehaves, run it directly from a terminal to see the"
    echo "real error:"
    echo "  \"$APP_PATH/Contents/MacOS/$APP_NAME\""
    exit 0
else
    printf '\n%s\n' "${RED}${BOLD}Verification still failing.${RESET}"
    echo "This usually means a native binary got packed INTO app.asar instead of"
    echo "staying unpacked on disk — a separate bug caused by whatever tool"
    echo "originally patched this app. See README.md, root cause #1."
    echo ""
    echo "The fix for that has to happen at re-pack time (see lib/unpack.js in"
    echo "this repo for a drop-in fix for patcher authors). Re-installing a"
    echo "fresh copy of Claude Desktop and re-applying your patch with an"
    echo "updated version of the tool is the most reliable path forward."
    exit 1
fi
