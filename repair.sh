#!/usr/bin/env bash
# claude-rtl-patcher — repair script
#
# Fixes two independent issues that can occur after patching Claude Desktop
# on macOS. Safe to run multiple times. Does NOT re-run the RTL/font patch —
# it only repairs whatever Claude.app you currently have.
#
#  1. "Claude Code process exited with code 127 — Malformed Mach-o file"
#     (stale/inconsistent nested code signatures)
#  2. "[FATAL] Integrity check failed for asar archive (X vs Y)" — the whole
#     app fails to launch (Electron's embedded ASAR integrity fuse)
#
# See TROUBLESHOOTING.md for the full explanation of both.

set -euo pipefail

APP_PATH="${1:-/Applications/Claude.app}"

if [ ! -d "$APP_PATH" ]; then
    echo "[!] $APP_PATH not found."
    echo "    Usage: ./repair.sh [path-to-Claude.app]"
    exit 1
fi

echo "Repairing: $APP_PATH"
echo ""

echo "[1/5] Disabling Electron's embedded ASAR integrity fuse..."
npx --yes @electron/fuses write --app "$APP_PATH" EnableEmbeddedAsarIntegrityValidation=off
echo ""

echo "[2/5] Removing all existing nested code signatures..."
codesign --remove-signature --deep "$APP_PATH" || true
echo "    Done (any errors above are expected for already-unsigned items)."
echo ""

echo "[3/5] Clearing extended attributes..."
xattr -cr "$APP_PATH"
echo "    Done."
echo ""

echo "[4/5] Signing from scratch (ad-hoc, deep)..."
codesign --force --deep --sign - "$APP_PATH"
echo "    Done."
echo ""

echo "[5/5] Verifying..."
if codesign --verify --deep --strict --verbose=4 "$APP_PATH"; then
    echo ""
    echo "=================================================="
    echo " Signature is valid. Fully quit Claude (Cmd+Q) and"
    echo " reopen it, then test the Claude Code tab."
    echo ""
    echo " If it still won't launch, run it directly from a"
    echo " terminal to see the real error:"
    echo "   $APP_PATH/Contents/MacOS/$(basename "$APP_PATH" .app)"
    echo "=================================================="
else
    echo ""
    echo "=================================================="
    echo " Verification still failing. This usually means a"
    echo " native binary got packed INTO app.asar instead of"
    echo " staying unpacked on disk — a separate bug, see"
    echo " TROUBLESHOOTING.md (root cause #1)."
    echo ""
    echo " Try: npx claude-rtl-patcher --restore"
    echo " then re-patch with the current version of the tool."
    echo "=================================================="
    exit 1
fi
