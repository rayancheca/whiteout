#!/usr/bin/env bash
#
# The gate. A session may not close unless this passes.
#
# Deliberately fast: the Core suite needs no simulator and runs in well under a second,
# so there is never an excuse to skip it. The iOS build is the slower half and exists to
# catch the errors that only surface when the app target compiles.

set -euo pipefail
cd "$(dirname "$0")/.."

SIMULATOR_ID="${WHITEOUT_SIM_ID:-10C15FE0-3D9A-40D5-9E45-C0702E906DF3}"
failures=0

echo "▸ Core test suite"
if (cd Core && swift test 2>&1 | tail -3); then
  echo "  ✓ tests passed"
else
  echo "  ✗ TESTS FAILED"
  failures=$((failures + 1))
fi

echo
echo "▸ Regenerating Xcode project"
# project.yml is the source of truth; the .xcodeproj is generated and gitignored, so a
# new source file is invisible to the build until this runs.
xcodegen generate >/dev/null 2>&1 && echo "  ✓ generated"

echo
echo "▸ iOS build"
# CODE_SIGNING_ALLOWED=NO because no signing team is configured for simulator builds.
if xcodebuild -project Whiteout.xcodeproj -scheme Whiteout \
     -destination "platform=iOS Simulator,id=${SIMULATOR_ID}" \
     -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 \
     | grep -qE "BUILD SUCCEEDED"; then
  echo "  ✓ build succeeded"
else
  echo "  ✗ BUILD FAILED — rerun the xcodebuild command directly for the error output"
  failures=$((failures + 1))
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "✅ GREEN — safe to hand off"
  exit 0
fi

echo "❌ RED — $failures check(s) failing. Do not hand off; fix or revert to green."
exit 1
