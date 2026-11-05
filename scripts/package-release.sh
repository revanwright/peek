#!/bin/bash
# Makes a shareable zip of the app: build/release/Peek-<version>.zip
#
# The compiler leaves debugging info in the app that records this Mac's folder
# paths (which include your username), so the release copy is stripped of it,
# re-signed, and checked before it's zipped.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
OUT="build/release"
APP="$OUT/Peek.app"
rm -rf "$OUT"
mkdir -p "$OUT"
cp -R build/Peek.app "$APP"

strip -S -x "$APP/Contents/MacOS/AIUsageTracker" "$APP/Contents/Helpers/ai-usage-hook"

# Re-sign the same way build-app.sh does (stripping invalidates the signature).
CERT_NAME="AI Usage Tracker Dev"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$CERT_NAME\""; then
    IDENTITY="$CERT_NAME"
else
    IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" --identifier com.peekmenubar.app.hook "$APP/Contents/Helpers/ai-usage-hook"
codesign --force --sign "$IDENTITY" --identifier com.peekmenubar.app "$APP"
codesign --verify --deep --strict "$APP"

# Refuse to package anything that still mentions this Mac's home folder or username.
if grep -r -a -q -e "$HOME" -e "/Users/$(id -un)" "$APP"; then
    echo "Stopped: the app still contains a path from this Mac." >&2
    exit 1
fi

ditto -c -k --keepParent "$APP" "$OUT/Peek-$VERSION.zip"
echo "Packaged: $OUT/Peek-$VERSION.zip"
