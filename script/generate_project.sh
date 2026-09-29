#!/usr/bin/env bash
# Regenerate AppleNativeLab.xcodeproj from project.yml. Needed only when targets, settings,
# packages, or schemes change: sources are synchronized folders.
source "$(dirname "$0")/lib.sh"
if ! command -v xcodegen >/dev/null; then
  echo "error: XcodeGen is required to regenerate the project (brew install xcodegen)." >&2
  echo "The committed AppleNativeLab.xcodeproj builds without it." >&2
  exit 69
fi
cd "$ROOT"
python3 script/generate_catalog.py
xcodegen generate --spec project.yml
