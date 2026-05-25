#!/usr/bin/env bash
set -euo pipefail

project="${PINES_XCODE_PROJECT:-Pines.xcodeproj}"
scheme="${PINES_XCODE_SCHEME:-Pines}"
derived_data="${PINES_DERIVED_DATA_PATH:-build/DerivedData}"
root="$(git rev-parse --show-toplevel)"
xcodegen=(bash "$root/scripts/ci/xcodegen.sh")
swiftpm_resolved_file="${PINES_SWIFTPM_PACKAGE_RESOLVED_FILE:-Package.resolved}"
xcode_resolved_file="${PINES_XCODE_PACKAGE_RESOLVED_FILE:-$project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved}"
snapshot_dir="${PINES_XCODE_VALIDATION_SNAPSHOT:-build/xcode-validation-snapshot}"
log_dir="${PINES_XCODE_BUILD_LOG_DIR:-build}"
xcode_package_flags=(
  -skipMacroValidation
  -skipPackagePluginValidation
  -onlyUsePackageVersionsFromResolvedFile
  -disableAutomaticPackageResolution
  -scmProvider
  system
)

mkdir -p "$log_dir"

usage() {
  cat <<'USAGE'
usage: run-xcode-validation.sh [all|prepare|generate|resolve|build-app|build-tests|run-tests|finalize]

Subcommands let GitHub Actions show granular Xcode validation phases while preserving
the generated-project and package-lock drift checks used by the full local run.
USAGE
}

require_snapshot() {
  if [ ! -d "$snapshot_dir" ]; then
    echo "::error::Xcode validation snapshot is missing. Run prepare first." >&2
    exit 1
  fi
}

snapshot_generated_project() {
  echo "Snapshotting generated project and package locks..."
  rm -rf "$snapshot_dir"
  mkdir -p "$snapshot_dir"

  if [ -e "$project" ]; then
    mkdir -p "$snapshot_dir/project"
    rsync -a \
      --exclude 'xcuserdata/' \
      --exclude '*.xcuserstate' \
      --exclude 'project.xcworkspace/xcshareddata/swiftpm/configuration/' \
      "$project/" "$snapshot_dir/project/"
  else
    touch "$snapshot_dir/project-missing"
  fi

  if [ ! -f "$swiftpm_resolved_file" ]; then
    echo "::error::$swiftpm_resolved_file is required for deterministic SwiftPM package resolution."
    exit 1
  fi
  if [ ! -f "$xcode_resolved_file" ]; then
    echo "::error::$xcode_resolved_file is required for deterministic Xcode app package resolution."
    exit 1
  fi

  cp "$swiftpm_resolved_file" "$snapshot_dir/Package.resolved"
  mkdir -p "$snapshot_dir/xcode-swiftpm"
  cp "$xcode_resolved_file" "$snapshot_dir/xcode-swiftpm/Package.resolved"
}

check_generated_project_drift() {
  require_snapshot
  echo "Checking generated project drift..."
  rm -rf "$project/project.xcworkspace/xcshareddata/swiftpm/configuration"

  if [ -e "$snapshot_dir/project-missing" ]; then
    if [ -e "$project" ]; then
      echo "::error::$project was generated but is not committed."
      exit 1
    fi
    return 0
  fi

  if ! diff -qr -x xcuserdata -x '*.xcuserstate' "$snapshot_dir/project" "$project" >/dev/null; then
    echo "::error::$project changed after pinned XcodeGen generation. Commit the generated project updates."
    diff -ru -x xcuserdata -x '*.xcuserstate' "$snapshot_dir/project" "$project" || true
    exit 1
  fi
}

check_package_resolution_drift() {
  require_snapshot
  echo "Checking package resolution drift..."

  if ! cmp -s "$snapshot_dir/Package.resolved" "$swiftpm_resolved_file"; then
    echo "::error::$swiftpm_resolved_file changed during Xcode validation. Commit the resolved SwiftPM graph."
    diff -u "$snapshot_dir/Package.resolved" "$swiftpm_resolved_file" || true
    exit 1
  fi

  if ! cmp -s "$snapshot_dir/xcode-swiftpm/Package.resolved" "$xcode_resolved_file"; then
    echo "::error::$xcode_resolved_file changed during Xcode validation. Commit the resolved Xcode app graph."
    diff -u "$snapshot_dir/xcode-swiftpm/Package.resolved" "$xcode_resolved_file" || true
    exit 1
  fi
}

generate_project() {
  require_snapshot
  echo "Generating Xcode project..."
  "${xcodegen[@]}" generate
  check_generated_project_drift
}

resolve_packages() {
  require_snapshot
  echo "Resolving Xcode package dependencies..."
  xcodebuild \
    -resolvePackageDependencies \
    -project "$project" \
    -scheme "$scheme" \
    -derivedDataPath "$derived_data" \
    "${xcode_package_flags[@]}"
  check_package_resolution_drift
}

build_app() {
  echo "Building iOS app without signing..."
  set -o pipefail
  xcodebuild \
    -project "$project" \
    -scheme "$scheme" \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$derived_data" \
    "${xcode_package_flags[@]}" \
    CODE_SIGNING_ALLOWED=NO \
    build | tee "$log_dir/xcodebuild.log"
}

first_available_iphone_simulator() {
  xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }'
}

simulator_required() {
  local required="${PINES_REQUIRE_SIMULATOR_TEST_RUN:-}"
  if [ -z "$required" ] && [ "${CI:-}" = "true" ]; then
    required=1
  fi
  [ "$required" = "1" ] || [ "$required" = "true" ]
}

simulator_id_file="$log_dir/ios-smoke-simulator-id"

build_tests() {
  echo "Building iOS runtime smoke tests..."

  local destination='generic/platform=iOS Simulator'
  local simulator_id
  simulator_id="$(first_available_iphone_simulator || true)"
  if [ -n "$simulator_id" ]; then
    destination="id=$simulator_id"
    printf '%s\n' "$simulator_id" > "$simulator_id_file"
  elif simulator_required; then
    echo "::error::No available iPhone simulator was found; CI requires runtime smoke tests."
    xcrun simctl list devices available || true
    exit 1
  else
    echo "::warning::No available iPhone simulator was found; smoke tests are build-verified with a generic simulator destination."
    rm -f "$simulator_id_file"
  fi

  set -o pipefail
  xcodebuild \
    -project "$project" \
    -scheme "$scheme" \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    "${xcode_package_flags[@]}" \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=YES \
    build-for-testing | tee "$log_dir/xcodebuild-tests.log"
}

run_tests() {
  if [ "${PINES_SKIP_SIMULATOR_TEST_RUN:-0}" = "1" ]; then
    echo "Skipping simulator test run because PINES_SKIP_SIMULATOR_TEST_RUN=1."
    return 0
  fi

  local simulator_id
  if [ -f "$simulator_id_file" ]; then
    simulator_id="$(cat "$simulator_id_file")"
  else
    simulator_id="$(first_available_iphone_simulator || true)"
  fi
  if [ -z "$simulator_id" ]; then
    if simulator_required; then
      echo "::error::No available iPhone simulator was found; CI requires runtime smoke tests."
      xcrun simctl list devices available || true
      exit 1
    fi
    echo "::warning::No available iPhone simulator was found; smoke tests were build-verified only."
    return 0
  fi

  : > "$log_dir/xcodebuild-test-run.log"
  run_xcode_test_phase "$simulator_id" "unit tests" -only-testing:PinesTests
  run_xcode_test_phase "$simulator_id" "UI smoke tests" -only-testing:PinesUITests
}

run_xcode_test_phase() {
  local simulator_id="$1"
  local label="$2"
  shift 2

  echo "Running iOS runtime smoke tests ($label)..."
  set -o pipefail
  xcodebuild \
    -project "$project" \
    -scheme "$scheme" \
    -destination "id=$simulator_id" \
    -derivedDataPath "$derived_data" \
    "${xcode_package_flags[@]}" \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=YES \
    "$@" \
    test-without-building | tee -a "$log_dir/xcodebuild-test-run.log"
}

finalize_validation() {
  require_snapshot
  echo "Restoring generated Xcode project..."
  "${xcodegen[@]}" generate
  check_generated_project_drift
  check_package_resolution_drift
}

run_all() {
  snapshot_generated_project
  generate_project
  resolve_packages
  build_app
  build_tests
  run_tests
  finalize_validation
}

command="${1:-all}"
case "$command" in
  all)
    run_all
    ;;
  prepare)
    snapshot_generated_project
    ;;
  generate)
    generate_project
    ;;
  resolve)
    resolve_packages
    ;;
  build-app)
    build_app
    ;;
  build-tests)
    build_tests
    ;;
  run-tests)
    run_tests
    ;;
  finalize)
    finalize_validation
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
