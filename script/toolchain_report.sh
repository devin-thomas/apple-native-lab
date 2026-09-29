#!/usr/bin/env bash
# Print the actual toolchain as Markdown, for docs/BUILD_STATUS.md.
source "$(dirname "$0")/lib.sh"
echo "| Item | Observed |"
echo "|---|---|"
echo "| Host macOS | $(sw_vers -productVersion) ($(sw_vers -buildVersion)) |"
echo "| Host chip | $(sysctl -n machdep.cpu.brand_string) |"
echo "| Xcode | $(xcodebuild -version | paste -sd ' ' -) |"
echo "| Swift | $(xcrun swift --version 2>/dev/null | head -1 | sed -E 's/.*(Apple Swift version [^ ]+).*/\1/') |"
echo "| SDKs | $(xcodebuild -showsdks 2>/dev/null | grep -oE '\-sdk [a-z]+[0-9.]+' | awk '{print $2}' | sort -u | paste -sd ' ' -) |"
echo "| XcodeGen | $(xcodegen --version 2>/dev/null | awk '{print $2}' || echo 'not installed') |"
