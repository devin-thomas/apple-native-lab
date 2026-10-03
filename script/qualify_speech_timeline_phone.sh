#!/usr/bin/env bash
# LAB-013-B's targeted launch/fixture regression. Run on the build host, through labr.
# Creates only its own simulator. No microphone, notification, model download, or device run.
source "$(dirname "$0")/lib.sh"
cd "$ROOT"
export LAB_SIMULATOR_PREFIX="${LAB_SIMULATOR_PREFIX:-NL LAB-013-B}"
OUTPUT="$ROOT/build/speech-phone-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUTPUT"
SPEECH_SIMULATOR="$(python3 script/simulator.py create iOS "$LAB_SIMULATOR_PREFIX repeated speech")"
trap 'python3 script/simulator.py delete "$SPEECH_SIMULATOR"' EXIT
REVISION="$(lab_revision)"
for iteration in {1..8}; do
  action=test-without-building
  [[ "$iteration" == 1 ]] && action=test
  bundle="$OUTPUT/run-$iteration.xcresult"
  if ! xcodebuild -project "$PROJECT" -scheme LabPhone-Core \
    -destination "id=$SPEECH_SIMULATOR" -derivedDataPath "$DERIVED" \
    -collect-test-diagnostics never \
    -only-testing:LabPhoneTests/SpeechTimelinePhoneTests \
    -only-testing:LabPhoneTests/SpeechTimelinePhoneQualificationTests \
    -resultBundlePath "$bundle" LAB_SOURCE_REVISION="$REVISION" "$action" -quiet \
    > "$OUTPUT/run-$iteration.log" 2>&1; then
    tail -30 "$OUTPUT/run-$iteration.log"
    exit 1
  fi
  xcrun xcresulttool get test-results summary --path "$bundle" > "$OUTPUT/run-$iteration.json"
  python3 - "$OUTPUT/run-$iteration.json" "$iteration" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
# xcodebuild may exit zero when a filter selected no tests: that is never a pass.
if result.get("result") != "Passed" or result.get("passedTests") != 3 or result.get("failedTests") != 0:
    sys.exit(f"Run {sys.argv[2]} did not pass all three targeted tests: {result}")
print(f"Speech Timeline phone run {sys.argv[2]}: 3 passed, 0 failed")
PY
done
printf 'Eight targeted runs passed; results: %s\n' "$OUTPUT"
