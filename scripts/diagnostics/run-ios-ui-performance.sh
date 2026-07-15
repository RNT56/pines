#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
project="${PINES_XCODE_PROJECT:-$root/Pines.xcodeproj}"
scheme="${PINES_PERFORMANCE_SCHEME:-PinesPerformance}"
derived_data="${PINES_PERFORMANCE_DERIVED_DATA:-$root/build/DerivedDataPerformance}"
artifacts="${PINES_PERFORMANCE_ARTIFACTS:-$root/artifacts/ui-performance-$timestamp}"
iterations="${PINES_PERFORMANCE_ITERATIONS:-5}"

mkdir -p "$artifacts"

first_available_iphone_simulator() {
  xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }'
}

destination="${PINES_PERFORMANCE_DESTINATION:-}"
if [ -z "$destination" ]; then
  simulator_id="$(first_available_iphone_simulator || true)"
  if [ -z "$simulator_id" ]; then
    printf 'No available iPhone simulator. Set PINES_PERFORMANCE_DESTINATION to an xcodebuild destination.\n' >&2
    exit 1
  fi
  destination="id=$simulator_id"
fi

case "$iterations" in
  ''|*[!0-9]*)
    printf 'PINES_PERFORMANCE_ITERATIONS must be an integer.\n' >&2
    exit 1
    ;;
esac

bash "$root/scripts/ci/xcodegen.sh" generate
bash "$root/scripts/ci/check-release-build-hygiene.sh"

worktree_state="clean"
if [ -n "$(git -C "$root" status --porcelain --untracked-files=normal)" ]; then
  worktree_state="dirty-provisional"
fi
xcode_version="$(xcodebuild -version | tr '\n' ';' | sed 's/;$//')"
host_os="$(sw_vers -productVersion) ($(sw_vers -buildVersion))"

cat > "$artifacts/environment.txt" <<EOF
commit=$(git -C "$root" rev-parse HEAD)
worktree_state=$worktree_state
scheme=$scheme
destination=$destination
iterations=$iterations
only_active_arch=YES
xcode=$xcode_version
host_os=$host_os
date_utc=$timestamp
EOF

PINES_RUN_UI_PERFORMANCE_TESTS=1 \
PINES_PERFORMANCE_ITERATIONS="$iterations" \
xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -configuration Release \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  -resultBundlePath "$artifacts/PinesPerformance.xcresult" \
  -only-testing:PinesUITests/PinesPerformanceUITests \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  -onlyUsePackageVersionsFromResolvedFile \
  -disableAutomaticPackageResolution \
  -scmProvider system \
  PINES_PERFORMANCE_ITERATION_COUNT="$iterations" \
  ONLY_ACTIVE_ARCH=YES \
  test | tee "$artifacts/xcodebuild.log"

printf 'Performance XCTest evidence: %s\n' "$artifacts"
printf 'Use docs/performance/RUNBOOK.md for physical-device Instruments acceptance.\n'
