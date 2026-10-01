#!/usr/bin/env bash
set -euo pipefail
TASK_PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TASK_PROBE_BUNDLE="$TASK_PROJECT_ROOT/build/LAB-040/ConfigurationProbe.xctest"
TASK_DEVELOPER_FRAMEWORKS="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/Library/Frameworks"
mkdir -p "$TASK_PROBE_BUNDLE/Contents/MacOS"
cat > "$TASK_PROBE_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ConfigurationProbe</string>
<key>CFBundleIdentifier</key><string>org.example.commerce-configuration-probe</string>
<key>CFBundlePackageType</key><string>BNDL</string>
</dict></plist>
PLIST
xcrun swiftc -emit-library -module-name CommerceConfigurationProbe \
  -I "$(xcode-select -p)/Platforms/MacOSX.platform/Developer/usr/lib" \
  -L "$(xcode-select -p)/Platforms/MacOSX.platform/Developer/usr/lib" \
  -Xlinker -rpath -Xlinker "$(xcode-select -p)/Platforms/MacOSX.platform/Developer/usr/lib" \
  -F "$TASK_DEVELOPER_FRAMEWORKS" -Xlinker -rpath -Xlinker "$TASK_DEVELOPER_FRAMEWORKS" \
  "$TASK_PROJECT_ROOT/Fixtures/LAB-040/ConfigurationProbe.swift" \
  -o "$TASK_PROBE_BUNDLE/Contents/MacOS/ConfigurationProbe"
TASK_XCTEST="$(xcrun --find xctest)"
LAB_COMMERCE_CONFIGURATION="$TASK_PROJECT_ROOT/Fixtures/LAB-040/Commerce.storekit" \
  DYLD_FRAMEWORK_PATH="$TASK_DEVELOPER_FRAMEWORKS" \
  DYLD_LIBRARY_PATH="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/usr/lib" \
  "$TASK_XCTEST" "$TASK_PROBE_BUNDLE" 2>&1 | tee "$TASK_PROJECT_ROOT/build/LAB-040/configuration-probe.log"
if grep -q "\[SKTestSession\] Error" "$TASK_PROJECT_ROOT/build/LAB-040/configuration-probe.log"; then
  echo "StoreKitTest refused its service configuration for this runner." >&2
  exit 1
fi
