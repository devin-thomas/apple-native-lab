#!/usr/bin/env bash
# Every automated check that needs no device, signing team, or network.
# Physical-device qualification is separate and recorded as evidence, never implied here.
#
# The four hosts are built and their smoke tests run on macOS and in iOS, watchOS, and tvOS
# simulators; the Watch and TV runs also run the LabSupport and LabCatalog package tests on those
# platforms, and the TV run drives the host with the remote. Each simulator is created for this
# run from the newest installed runtime and deleted when its step ends, or when the run stops,
# so no existing simulator is used or changed. Name them with LAB_SIMULATOR_PREFIX (default
# "Native Lab smoke").
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

step() { printf '\n==> %s\n' "$1"; }

REVISION="$(lab_revision)"
SIMULATOR_PREFIX="${LAB_SIMULATOR_PREFIX:-Native Lab smoke}"
CREATED_SIMULATORS=()

delete_created_simulators() {
  local id
  for id in ${CREATED_SIMULATORS[@]+"${CREATED_SIMULATORS[@]}"}; do
    python3 script/simulator.py delete "$id" || echo "warning: could not delete simulator $id" >&2
  done
  CREATED_SIMULATORS=()
}
trap delete_created_simulators EXIT

# Creates a simulator for a platform (iOS, watchOS, tvOS) and sets SIMULATOR to its UDID.
new_simulator() {
  SIMULATOR="$(python3 script/simulator.py create "$1" "$SIMULATOR_PREFIX $1 $$")"
  CREATED_SIMULATORS+=("$SIMULATOR")
}

# Runs a host scheme's test action in a simulator. Diagnostics collection is off: after a pass it
# can wait minutes on `simctl diagnose`, and a failure's own output already names the test.
host_tests() {
  xcodebuild -project "$PROJECT" -scheme "$1" -destination "id=$2" -derivedDataPath "$DERIVED" \
    -collect-test-diagnostics never LAB_SOURCE_REVISION="$REVISION" test -quiet
}

# Runs a host scheme's tests on a new simulator for a platform. On a loaded machine a fresh
# simulator sometimes fails to launch the app or the test runner before any test runs; only that
# failure, recognized by its message, earns one more try on another new simulator. A failing test
# is never retried.
simulator_host_tests() {
  local scheme="$1" platform="$2" log status
  log="$(mktemp -t lab-host-tests)"
  new_simulator "$platform"
  set +e
  host_tests "$scheme" "$SIMULATOR" 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  set -e
  delete_created_simulators
  if [[ "$status" != 0 ]] && grep -qE "failed to launch|Failed to install or launch the test runner|test runner hung before establishing connection" "$log" \
     && ! grep -qE "^Failing tests:" "$log"; then
    echo "note: the $platform simulator failed to start the test run; retrying once on a new simulator" >&2
    new_simulator "$platform"
    status=0
    host_tests "$scheme" "$SIMULATOR" || status=$?
    delete_created_simulators
  fi
  rm -f "$log"
  return "$status"
}

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

step "LabStaging package tests"
swift test --package-path Packages/LabStaging --quiet

step "LabDemo package tests"
swift test --package-path Packages/LabDemo --quiet

step "LabFeatures package tests"
swift test --package-path Packages/LabFeatures --quiet

# The Mac host tests drive the app in the logged-in GUI session, which concurrent runs on one Mac
# share. When LAB_MAC_UI_LOCK names a lock file, this step waits for it (lockf), so runs from several
# checkouts on one shared machine take turns here and run their other steps in parallel.
with_mac_ui_lock() {
  if [[ -n "${LAB_MAC_UI_LOCK:-}" ]]; then lockf -k "$LAB_MAC_UI_LOCK" "$@"; else "$@"; fi
}

step "Mac host hosted smoke tests (LabMac-Core)"
with_mac_ui_lock xcodebuild -project "$PROJECT" -scheme LabMac-Core -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" LAB_SOURCE_REVISION="$REVISION" test -quiet

step "iPhone host smoke tests in an iOS simulator (LabPhone-Core)"
simulator_host_tests LabPhone-Core iOS

step "Watch host smoke tests, then LabSupport and LabCatalog tests, in a watchOS simulator (LabWatch)"
simulator_host_tests LabWatch watchOS

step "Apple TV host smoke and remote focus tests, then LabSupport and LabCatalog tests, in a tvOS simulator (LabTV)"
simulator_host_tests LabTV tvOS

step "Release builds of every profile match Config/ProductPolicy.txt (build_manifest.py)"
python3 script/build_manifest.py

printf '\nAll automated checks passed. Device qualification is not part of this script.\n'
