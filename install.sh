#!/bin/bash
# Build iQualize and install to /Applications
set -e

cd "$(dirname "$0")"

echo "Building iQualize..."
swift build -c release 2>&1 | tail -5

APP=/Applications/iQualize.app
BIN="$APP/Contents/MacOS/iQualize"
SRC=.build/release/iQualize

mkdir -p "$APP/Contents/MacOS"

# Only replace binary if it actually changed — preserves TCC permissions (cdhash stays the same)
if [ -f "$BIN" ] && cmp -s "$SRC" "$BIN"; then
    echo "Binary unchanged — skipping copy (TCC permissions preserved)"
else
    cp -f "$SRC" "$BIN"
    # Codesign with stable identity
    SIGN_ID="Apple Development"
    if [ -n "$SIGN_ID" ]; then
        codesign --force --sign "$SIGN_ID" "$APP" 2>/dev/null && echo "Signed with: $SIGN_ID"
    fi
    echo "Binary updated"
fi

# Always update Info.plist
cp -f Sources/iQualize/Info.plist "$APP/Contents/Info.plist"

# Strip provenance xattr to prevent macOS security policy launch blocks
xattr -rc "$APP" 2>/dev/null

echo "Installed to /Applications/iQualize.app"
