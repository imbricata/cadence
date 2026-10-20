#!/bin/zsh
# usage: scripts/ios-shot.sh <name> [extra launch args, e.g. -CadenceTab inbox]
# Env: UI=light|dark (default light), TEXT=<content size category> (default large), SHOT_DELAY (default 4)
# Installs the built iOS app on the iPhone 17 simulator and saves /tmp/shots/ios-<name>.png.
set -e
cd "$(dirname "$0")/.."
UDID=CF870154-FB8D-43AD-ACD8-A8842B46A1AC
APP=/tmp/cadence-dd/Build/Products/Debug-iphonesimulator/Cadence.app
mkdir -p /tmp/shots
xcrun simctl bootstatus $UDID -b >/dev/null 2>&1
xcrun simctl ui $UDID appearance ${UI:-light}
xcrun simctl ui $UDID content_size ${TEXT:-large}
xcrun simctl terminate $UDID com.theocoronges.cadence 2>/dev/null || true
xcrun simctl install $UDID "$APP"
xcrun simctl launch $UDID com.theocoronges.cadence -CadenceDemo YES "${@:2}" >/dev/null
sleep ${SHOT_DELAY:-4}
xcrun simctl io $UDID screenshot "/tmp/shots/ios-$1.png" 2>/dev/null
echo "/tmp/shots/ios-$1.png"
