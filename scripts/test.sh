#!/bin/bash
# Runs the project's checks.
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
FLAGS=(-swift-version 6 -sdk "$SDK" -target arm64-apple-macosx15.0)
mkdir -p build

echo "== Cowork status"
swiftc "${FLAGS[@]}" Sources/AIUsageTracker/ClaudeCode/CoworkWatcher.swift Tests/CoworkCheck/main.swift -o build/cowork-check
build/cowork-check

echo; echo "== App time counting"
swiftc "${FLAGS[@]}" Sources/AIUsageTracker/AppTime/AppTimeLedger.swift Tests/AppTimeCheck/main.swift -o build/apptime-check
build/apptime-check
