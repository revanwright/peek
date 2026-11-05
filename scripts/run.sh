#!/bin/bash
# Rebuilds the app, installs it to ~/Applications, quits any running copy,
# and opens the new one. Extra arguments are passed to the app, e.g.:
#   ./scripts/run.sh --design-preview --appearance dark
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

INSTALLED="$HOME/Applications/Peek.app"
pkill -x AIUsageTracker 2>/dev/null || true
sleep 0.5
mkdir -p "$HOME/Applications"
rm -rf "$INSTALLED"
cp -R "build/Peek.app" "$INSTALLED"

if [ $# -gt 0 ]; then
    open "$INSTALLED" --args "$@"
else
    open "$INSTALLED"
fi
