#!/bin/bash
# Build iQualize and install to ~/Applications for Spotlight/Dock access

set -e

echo "Building iQualize..."
xcodebuild -project iQualize.xcodeproj -scheme iQualize -configuration Release build 2>&1 | tail -5

APP_PATH=$(xcodebuild -project iQualize.xcodeproj -scheme iQualize -configuration Release -showBuildSettings 2>/dev/null | grep " BUILT_PRODUCTS_DIR" | awk '{print $3}')

mkdir -p ~/Applications

echo "Installing to ~/Applications/iQualize.app..."
rm -rf ~/Applications/iQualize.app
cp -R "$APP_PATH/iQualize.app" ~/Applications/iQualize.app

echo "Done! iQualize is now available in Spotlight and can be dragged to the Dock."
