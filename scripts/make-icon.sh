#!/bin/bash
# Redraws the app icon and saves it as Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk scripts/make-icon.swift -o build/make-icon
rm -rf build/AppIcon.iconset
build/make-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
echo "Saved Resources/AppIcon.icns"
