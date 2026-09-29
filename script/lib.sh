# Shared helpers for script/ entry points. Source this file; do not run it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/AppleNativeLab.xcodeproj"
DERIVED="$ROOT/build/DerivedData"

# The Git revision baked into Info.plist, marked when the working tree has changes.
lab_revision() {
  local revision
  revision="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  if [[ "$revision" != unknown && -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]]; then
    revision="$revision-dirty"
  fi
  echo "$revision"
}

bundle_id() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1"
}

# Device identifiers are passed to xcodebuild and devicectl as data, never interpolated into a shell.
require_device_id() {
  if [[ ! "${1:-}" =~ ^[A-Za-z0-9-]+$ ]]; then
    echo "error: device id must contain only letters, digits, and hyphens" >&2
    exit 64
  fi
}

require_local_signing() {
  if [[ ! -f "$ROOT/Config/Local.xcconfig" ]]; then
    echo "error: device builds need Config/Local.xcconfig. Copy Config/Local.xcconfig.example and set your team." >&2
    exit 78
  fi
}

# Stops only the copy of the lab's Mac app running from this exact bundle, so a build from one
# checkout never quits another checkout's build or the installed app.
stop_app_at() {
  local executable="$1/Contents/MacOS/NativeLab" pid path stopped=0
  while read -r pid path; do
    if [[ "$path" == "$executable" ]]; then
      kill "$pid" 2>/dev/null && stopped=1
    fi
  done < <(ps -axww -o pid=,comm=)
  if [[ "$stopped" == 1 ]]; then sleep 1; fi
}
