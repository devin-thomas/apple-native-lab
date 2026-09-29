#!/usr/bin/env bash
# Build a Release Mac host and install it as ~/Applications/Native Lab.app, then open it.
source "$(dirname "$0")/lib.sh"

xcodebuild -project "$PROJECT" -scheme LabMac-Core -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  LAB_SOURCE_REVISION="$(lab_revision)" build -quiet

SOURCE="$DERIVED/Build/Products/Release/NativeLab.app"
TARGET="$HOME/Applications/Native Lab.app"
stop_app_at "$TARGET"
mkdir -p "$HOME/Applications"
rm -rf "$TARGET"
ditto "$SOURCE" "$TARGET"
codesign --verify --deep --strict "$TARGET"
open "$TARGET"
echo "Installed and opened $TARGET (revision $(lab_revision))"
