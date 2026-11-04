#!/bin/bash
# Saves light and dark pictures of the dropdown and every Settings tab,
# using clearly-labeled sample data, into build/design-shots.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
INSTALLED="$HOME/Applications/AI Usage Tracker.app"
pkill -x AIUsageTracker 2>/dev/null || true
rm -rf "$INSTALLED" build/design-shots
cp -R "build/AI Usage Tracker.app" "$INSTALLED"

for mode in light dark; do
    open -W -n "$INSTALLED" --args --design-preview --appearance "$mode" --snapshot "$PWD/build/design-shots"
done
ls build/design-shots
