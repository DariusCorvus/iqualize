#!/bin/bash
# Build iQualize and install to /Applications
set -e

cd "$(dirname "$0")"

echo "Building iQualize..."
swift build -c release 2>&1 | tail -5

APP=/Applications/iQualize.app
BIN="$APP/Contents/MacOS/iQualize"
SRC="$(swift build -c release --show-bin-path)/iQualize"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Only replace binary if it actually changed — preserves TCC permissions (cdhash stays the same)
if [ -f "$BIN" ] && cmp -s "$SRC" "$BIN"; then
    echo "Binary unchanged — skipping copy (TCC permissions preserved)"
else
    cp -f "$SRC" "$BIN"
    # Codesign with stable identity
    SIGN_ID="Apple Development"
    if [ -n "$SIGN_ID" ]; then
        codesign --force --sign "$SIGN_ID" --entitlements iQualize.entitlements "$APP" 2>/dev/null && echo "Signed with: $SIGN_ID"
    fi
    echo "Binary updated"
fi

# Copy app icon
cp -f Sources/iQualize/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Always update Info.plist — then re-sign if it changed (plist change invalidates signature)
if ! cmp -s Sources/iQualize/Info.plist "$APP/Contents/Info.plist"; then
    cp -f Sources/iQualize/Info.plist "$APP/Contents/Info.plist"
    codesign --force --sign "Apple Development" --entitlements iQualize.entitlements "$APP" 2>/dev/null && echo "Re-signed (Info.plist changed)"
else
    cp -f Sources/iQualize/Info.plist "$APP/Contents/Info.plist"
fi

# Strip provenance xattr to prevent macOS security policy launch blocks
xattr -rc "$APP" 2>/dev/null

echo "Installed to /Applications/iQualize.app"
