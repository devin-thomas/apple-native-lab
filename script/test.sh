#!/usr/bin/env bash
# Every automated check that needs no device, signing team, or network.
# Physical-device qualification is separate and recorded as evidence, never implied here.
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

step() { printf '\n==> %s\n' "$1"; }

step "Catalog matches experiment specs"
python3 script/generate_catalog.py --check

step "LabSupport package tests"
swift test --package-path Packages/LabSupport --quiet

step "LabFeatures package tests"
swift test --package-path Packages/LabFeatures --quiet

step "Mac host hosted smoke tests (LabMac-Core)"
xcodebuild -project "$PROJECT" -scheme LabMac-Core -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" LAB_SOURCE_REVISION="$(lab_revision)" test -quiet

step "iPhone host compiles for the simulator (LabPhone-Core)"
xcodebuild -project "$PROJECT" -scheme LabPhone-Core -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED" build -quiet

step "Watch host compiles for the simulator (LabWatch)"
xcodebuild -project "$PROJECT" -scheme LabWatch -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath "$DERIVED" build -quiet

printf '\nAll automated checks passed. Device qualification is not part of this script.\n'
