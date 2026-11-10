#!/bin/bash
# Builds build/SwitchTab.app from the Swift package. No Xcode needed, only Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/SwitchTab.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SwitchTab "$APP/Contents/MacOS/SwitchTab"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature. macOS ties privacy permissions to it, so permissions must be
# granted again after each rebuild.
codesign --force --sign - --identifier com.danielrojansky.switchtab "$APP"

echo "Built $APP"
