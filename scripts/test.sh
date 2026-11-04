#!/bin/bash
# Runs the project's checks.
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
mkdir -p build
swiftc -swift-version 6 -sdk "$SDK" -target arm64-apple-macosx15.0 \
    Sources/AIUsageTracker/ClaudeCode/CoworkWatcher.swift Tests/CoworkCheck/main.swift \
    -o build/cowork-check
build/cowork-check
