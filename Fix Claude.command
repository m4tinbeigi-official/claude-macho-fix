#!/usr/bin/env bash
# Double-click this file in Finder to repair Claude Desktop.
# It just opens a Terminal window and runs repair.sh for you — no typing required.
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
./repair.sh
echo ""
read -r -p "Press Enter to close this window..." _
