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
new_simulator iOS
host_tests LabPhone-Core "$SIMULATOR"
delete_created_simulators

step "Watch host smoke tests, then LabSupport and LabCatalog tests, in a watchOS simulator (LabWatch)"
new_simulator watchOS
host_tests LabWatch "$SIMULATOR"
delete_created_simulators

step "Apple TV host smoke and remote focus tests, then LabSupport and LabCatalog tests, in a tvOS simulator (LabTV)"
new_simulator tvOS
host_tests LabTV "$SIMULATOR"
delete_created_simulators

step "Release builds of every profile match Config/ProductPolicy.txt (build_manifest.py)"
python3 script/build_manifest.py

printf '\nAll automated checks passed. Device qualification is not part of this script.\n'
