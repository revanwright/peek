#!/bin/bash
# Builds "AI Usage Tracker.app" into ./build without Xcode, using Apple's
# Swift compiler from the Command Line Tools directly.
#
# Signing: if a code-signing certificate named "AI Usage Tracker Dev" exists in
# your login keychain, it is used so Keychain stops re-asking for permission
# after every rebuild. Otherwise the app is signed "ad hoc" (works, but macOS
# may ask "allow access?" again after each rebuild).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/AI Usage Tracker.app"
CERT_NAME="AI Usage Tracker Dev"
OPTIMIZE="${OPTIMIZE:--Onone}"   # OPTIMIZE=-O for a faster release build

# Use the macOS 26 SDK: the macOS 27 SDK's SwiftUI needs a compiler plugin
# ("SwiftUIMacros") that only ships inside Xcode, not the Command Line Tools.
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"

mkdir -p build
SOURCES=()
while IFS= read -r -d '' file; do SOURCES+=("$file"); done < <(find Sources/AIUsageTracker -name '*.swift' -print0)

swiftc \
    -parse-as-library \
    -swift-version 6 \
    -target arm64-apple-macosx15.0 \
    -sdk "$SDK" \
    "$OPTIMIZE" -g \
    -o build/AIUsageTracker \
    "${SOURCES[@]}"

# The small helper Claude Code runs for each hook event (Foundation only, starts fast).
swiftc \
    -swift-version 6 \
    -target arm64-apple-macosx15.0 \
    -sdk "$SDK" \
    -O \
    -o build/ai-usage-hook \
    Sources/Hook/main.swift

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
mv build/AIUsageTracker "$APP/Contents/MacOS/AIUsageTracker"
mv build/ai-usage-hook "$APP/Contents/Helpers/ai-usage-hook"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if security find-identity -p codesigning 2>/dev/null | grep -q "\"$CERT_NAME\""; then
    IDENTITY="$CERT_NAME"
else
    IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" --identifier com.evanwright.AIUsageTracker.hook "$APP/Contents/Helpers/ai-usage-hook"
codesign --force --sign "$IDENTITY" --identifier com.evanwright.AIUsageTracker "$APP"

echo "Built: $APP (signed with: ${IDENTITY/-/ad hoc})"
