#!/bin/zsh
# usage: scripts/mac-shot.sh <name> [extra launch args, e.g. -CadenceSection inbox]
# Launches the built Mac app in demo mode and saves /tmp/shots/mac-<name>.png.
set -e
cd "$(dirname "$0")/.."
APP=/tmp/cadence-dd/Build/Products/Debug/Cadence.app
mkdir -p /tmp/shots
[ -x /tmp/windowid ] || swiftc scripts/windowid.swift -o /tmp/windowid
pkill -x Cadence 2>/dev/null || true
sleep 0.5
open -n "$APP" --args -CadenceDemo YES "${@:2}"
sleep ${SHOT_DELAY:-4}
WID=$(/tmp/windowid Cadence)
[ -n "$WID" ] || { echo "no window found"; pkill -x Cadence; exit 1; }
screencapture -o -x -l "$WID" "/tmp/shots/mac-$1.png"
[ -n "$SHOT_KEEP" ] || pkill -x Cadence
echo "/tmp/shots/mac-$1.png"
