#!/usr/bin/env bash
# Build LabPhone-Core for a connected iPhone or iPad, install it, and launch it.
# Usage: script/install_phone.sh               list connected devices
#        script/install_phone.sh <device-id>   build, install, launch
source "$(dirname "$0")/lib.sh"

if [[ $# -lt 1 ]]; then
  echo "Connected iOS devices:"
  xcodebuild -project "$PROJECT" -scheme LabPhone-Core -showdestinations 2>/dev/null \
    | grep 'platform:iOS,' | grep -v -e Simulator -e placeholder || echo "  (none)"
  echo "usage: $0 <device-id>"
  exit 64
fi
require_device_id "$1"
require_local_signing
DEVICE="$1"

xcodebuild -project "$PROJECT" -scheme LabPhone-Core -configuration Debug \
  -destination "id=$DEVICE" -derivedDataPath "$DERIVED" -allowProvisioningUpdates \
  LAB_SOURCE_REVISION="$(lab_revision)" build -quiet

APP="$DERIVED/Build/Products/Debug-iphoneos/NativeLab.app"
BUNDLE="$(bundle_id "$APP/Info.plist")"
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --terminate-existing --device "$DEVICE" "$BUNDLE"
