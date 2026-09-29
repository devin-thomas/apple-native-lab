#!/usr/bin/env bash
# Build the Mac host (scheme LabMac-Core) and open the real .app bundle.
# Stops only a copy already running from this same build output first.
# Usage: script/build_and_run.sh [Debug|Release]
source "$(dirname "$0")/lib.sh"

CONFIGURATION="${1:-Debug}"
case "$CONFIGURATION" in Debug|Release) ;; *) echo "usage: $0 [Debug|Release]" >&2; exit 64 ;; esac

xcodebuild -project "$PROJECT" -scheme LabMac-Core -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  LAB_SOURCE_REVISION="$(lab_revision)" build -quiet

APP="$DERIVED/Build/Products/$CONFIGURATION/NativeLab.app"
stop_app_at "$APP"
open "$APP"
echo "Opened $APP ($(bundle_id "$APP/Contents/Info.plist"), revision $(lab_revision))"
