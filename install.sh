#!/bin/bash
# Build iQualize and install to ~/Applications for Spotlight/Dock access
set -e

cd "$(dirname "$0")"

echo "Building iQualize..."
swift build -c release 2>&1 | tail -5

APP=/Applications/iQualize.app
mkdir -p "$APP/Contents/MacOS"

# Copy binary — always overwrites, keeping the same app identity for macOS permissions
cp -f .build/release/iQualize "$APP/Contents/MacOS/iQualize"

# Always update Info.plist so version stays current
cp -f Sources/iQualize/Info.plist "$APP/Contents/Info.plist"

echo "Installed to /Applications/iQualize.app"
echo "You can drag it to the Dock or find it in Spotlight."
