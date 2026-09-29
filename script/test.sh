#!/usr/bin/env bash
# Every automated check that needs no device, signing team, or network.
# Physical-device qualification is separate and recorded as evidence, never implied here.
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

step() { printf '\n==> %s\n' "$1"; }

step "Repository validators (links, tickets, experiments, catalog, evidence, workflow policy)"
python3 script/validate/all.py

step "Validator self-tests (negative fixtures in temporary copies)"
python3 -B -m unittest discover -s script/validate/tests

step "LabSupport package tests"
swift test --package-path Packages/LabSupport --quiet

step "LabDomain package tests"
swift test --package-path Packages/LabDomain --quiet

step "LabStore package tests"
swift test --package-path Packages/LabStore --quiet

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

step "Release builds of every profile match Config/ProductPolicy.txt (build_manifest.py)"
python3 script/build_manifest.py

printf '\nAll automated checks passed. Device qualification is not part of this script.\n'
