#!/bin/bash
# Builds Switch Tab, installs it to /Applications and starts it.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/setup-signing.sh
./scripts/build-app.sh

pkill -x SwitchTab 2>/dev/null || true
sleep 1
ditto build/SwitchTab.app /Applications/SwitchTab.app
open /Applications/SwitchTab.app
echo "Installed /Applications/SwitchTab.app"
