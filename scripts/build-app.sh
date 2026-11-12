#!/bin/bash
# Builds build/SwitchTab.app from the Swift package. No Xcode needed, only Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/SwitchTab.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SwitchTab "$APP/Contents/MacOS/SwitchTab"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# App icon. Regenerate with: swift scripts/make-icon.swift
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

NAME="SwitchTab Local Signing"
KEYCHAIN="$HOME/Library/Keychains/switchtab-signing.keychain-db"
PWFILE="$HOME/Library/Application Support/SwitchTab/signing-keychain-password"
BUNDLE_ID="com.danielrojansky.switchtab"

if [ -f "$KEYCHAIN" ] && [ -f "$PWFILE" ]; then
    # Stable signature: privacy permissions survive rebuilds.
    security unlock-keychain -p "$(cat "$PWFILE")" "$KEYCHAIN"
    codesign --force --sign "$NAME" --keychain "$KEYCHAIN" --identifier "$BUNDLE_ID" "$APP"
else
    # Ad-hoc signature: permissions must be granted again after each rebuild.
    # Run scripts/setup-signing.sh once to avoid that.
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi

echo "Built $APP"
