#!/usr/bin/env bash
# Build LabWatch for a paired Apple Watch in Developer Mode, install it, and launch it.
# Usage: script/install_watch.sh               list Watch destinations and their errors
#        script/install_watch.sh <device-id>   build, install, launch
source "$(dirname "$0")/lib.sh"

if [[ $# -lt 1 ]]; then
  echo "watchOS destinations (usable only when no error is shown):"
  xcodebuild -project "$PROJECT" -scheme LabWatch -showdestinations 2>/dev/null \
    | grep 'platform:watchOS,' | grep -v -e Simulator -e placeholder || echo "  (none: see docs/DEVICE_SETUP.md)"
  echo "usage: $0 <device-id>"
  exit 64
fi
require_device_id "$1"
require_local_signing
DEVICE="$1"

xcodebuild -project "$PROJECT" -scheme LabWatch -configuration Debug \
  -destination "id=$DEVICE" -derivedDataPath "$DERIVED" -allowProvisioningUpdates \
  LAB_SOURCE_REVISION="$(lab_revision)" build -quiet

APP="$DERIVED/Build/Products/Debug-watchos/NativeLabWatch.app"
BUNDLE="$(bundle_id "$APP/Info.plist")"
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --terminate-existing --device "$DEVICE" "$BUNDLE"
