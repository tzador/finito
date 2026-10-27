#!/bin/bash
# Builds Confetti.app into ./build. Usage: ./build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release 2>&1 | tail -n 3

APP=build/Confetti.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Confetti "$APP/Contents/MacOS/Confetti"
cp Info.plist "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Confetti >/dev/null 2>&1 || true
    rm -rf /Applications/Confetti.app
    cp -R "$APP" /Applications/Confetti.app
    echo "Installed to /Applications/Confetti.app"
    open /Applications/Confetti.app
fi
