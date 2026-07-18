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

Set PINES_XCODE_UI_TEST_MODE=smoke to run the bounded critical-journey UI shards used
by required CI. The default full mode runs the complete PinesUITests target.
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

create_ephemeral_iphone_simulator() {
  local timeout_seconds="${PINES_SIMULATOR_OPERATION_TIMEOUT_SECONDS:-180}"
  local device_type="${PINES_SIMULATOR_DEVICE_TYPE:-}"
  local runtime="${PINES_SIMULATOR_RUNTIME:-}"

  if [ -z "$device_type" ]; then
    device_type="$(xcrun simctl list devicetypes | awk -F '[()]' '/iPhone/ { print $2; exit }')"
  fi
  if [ -z "$runtime" ]; then
    runtime="$(xcrun simctl list runtimes available | awk '/^iOS / { value=$NF } END { print value }')"
  fi
  if [ -z "$device_type" ] || [ -z "$runtime" ]; then
    echo "::error::Unable to select an available iPhone device type and iOS runtime." >&2
    xcrun simctl list devicetypes || true
    xcrun simctl list runtimes available || true
    return 1
  fi

  echo "Creating an ephemeral iPhone simulator for this validation run..." >&2
  run_with_timeout "$timeout_seconds" \
    xcrun simctl create "Pines-CI-$$-$(date +%s)" "$device_type" "$runtime"
}

simulator_required() {
  local required="${PINES_REQUIRE_SIMULATOR_TEST_RUN:-}"
  if [ -z "$required" ] && [ "${CI:-}" = "true" ]; then
    required=1
  fi
  [ "$required" = "1" ] || [ "$required" = "true" ]
}

simulator_id_file="$log_dir/ios-smoke-simulator-id"
ui_test_simulator_id=""

build_tests() {
  echo "Building iOS runtime smoke tests..."

  local destination='generic/platform=iOS Simulator'
  local simulator_id
  if [ "${CI:-}" = "true" ]; then
    simulator_id="$(create_ephemeral_iphone_simulator || true)"
  else
    simulator_id="$(first_available_iphone_simulator || true)"
  fi
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

  trap cleanup_test_simulator EXIT INT TERM
  : > "$log_dir/xcodebuild-test-run.log"
  prepare_test_simulator "$simulator_id"
  run_xcode_test_phase "$simulator_id" "unit tests" -only-testing:PinesTests
  run_ui_tests "$simulator_id"
  cleanup_test_simulator
  trap - EXIT INT TERM
}

run_ui_tests() {
  local simulator_id="$1"
  local mode="${PINES_XCODE_UI_TEST_MODE:-full}"

  case "$mode" in
    smoke)
      local smoke_tests=(
        "PinesUITests/PinesUITests/testLaunchNavigateTabsCreateChatAndTypeDraft"
        "PinesUITests/PinesUITests/testAccessibilityTextSizeKeepsPrimarySurfacesReachable"
        "PinesUITests/PinesUITests/testArtifactsLibraryAndImageStudio"
        "PinesUITests/PinesUITests/testArtifactsVideoAndSpeechConfiguration"
        # Keep the research journey split: accessibility snapshot latency can
        # accumulate inside one long UI-test process even on a fresh clone.
        "PinesUITests/PinesUITests/testArtifactsResearchConfiguration"
        "PinesUITests/PinesUITests/testArtifactsResearchComposerFlow"
        "PinesUITests/PinesUITests/testArtifactsRunningResearch"
      )
      if [ "${CI:-}" = "true" ]; then
        prepare_ui_test_simulator_base "$simulator_id"
      fi

      local index=0
      local test
      for test in "${smoke_tests[@]}"; do
        index=$((index + 1))
        if [ "${CI:-}" = "true" ]; then
          # Xcode's accessibility snapshot service can degrade across independent
          # UI-test invocations on one simulator. Give each shard a clone of the
          # fully migrated base so services are fresh without another erase/boot.
          run_ui_test_on_clone "$simulator_id" "$test" "$index"
        else
          run_xcode_test_phase \
            "$simulator_id" \
            "UI smoke: ${test##*/}" \
            "-only-testing:$test"
        fi
      done
      ;;
    full)
      run_xcode_test_phase "$simulator_id" "full UI test suite" -only-testing:PinesUITests
      ;;
    *)
      echo "::error::Unsupported PINES_XCODE_UI_TEST_MODE '$mode'; expected 'smoke' or 'full'." >&2
      return 2
      ;;
  esac
}

run_xcode_test_phase() {
  local simulator_id="$1"
  local label="$2"
  local timeout_seconds="${PINES_XCODE_TEST_TIMEOUT_SECONDS:-}"
  local attempts="${PINES_XCODE_TEST_ATTEMPTS:-}"
  local failure_annotation="${PINES_XCODE_TEST_FAILURE_ANNOTATION:-error}"
  shift 2

  if [ "$failure_annotation" != "error" ] && [ "$failure_annotation" != "warning" ]; then
    echo "::error::PINES_XCODE_TEST_FAILURE_ANNOTATION must be 'error' or 'warning'." >&2
    return 2
  fi

  if [ -z "$timeout_seconds" ]; then
    if [ "${CI:-}" = "true" ]; then
      timeout_seconds=720
    else
      timeout_seconds=0
    fi
  fi
  if [ -z "$attempts" ]; then
    if [ "${CI:-}" = "true" ]; then
      attempts=1
    else
      attempts=2
    fi
  fi

  local attempt
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    echo "Running iOS runtime smoke tests ($label, attempt $attempt)..."
    set -o pipefail
    if run_with_timeout "$timeout_seconds" \
      xcodebuild \
        -project "$project" \
        -scheme "$scheme" \
        -destination "id=$simulator_id" \
        -derivedDataPath "$derived_data" \
        "${xcode_package_flags[@]}" \
        CODE_SIGNING_ALLOWED=NO \
        ONLY_ACTIVE_ARCH=YES \
        "$@" \
        test-without-building | tee -a "$log_dir/xcodebuild-test-run.log"; then
      return 0
    fi

    local status="${PIPESTATUS[0]}"
    if [ "$attempt" -eq "$attempts" ]; then
      echo "::${failure_annotation}::$label failed after $attempt attempt(s) (status $status)." >&2
      return "$status"
    fi

    echo "::warning::$label did not complete (status $status); restarting the simulator before retry." >&2
    prepare_test_simulator "$simulator_id"
  done
}

prepare_test_simulator() {
  local simulator_id="$1"

  if [ "${CI:-}" != "true" ]; then
    return 0
  fi

  echo "Preparing simulator $simulator_id for runtime tests..."
  local timeout_seconds="${PINES_SIMULATOR_OPERATION_TIMEOUT_SECONDS:-180}"
  run_with_timeout "$timeout_seconds" xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
  run_with_timeout "$timeout_seconds" xcrun simctl erase "$simulator_id"
  run_with_timeout "$timeout_seconds" xcrun simctl boot "$simulator_id"
  if ! run_with_timeout "$timeout_seconds" xcrun simctl bootstatus "$simulator_id" -b; then
    echo "::error::Simulator $simulator_id did not finish booting within ${timeout_seconds}s." >&2
    xcrun simctl diagnose -b --no-archive || true
    return 1
  fi
}

prepare_ui_test_simulator_base() {
  local simulator_id="$1"
  local timeout_seconds="${PINES_SIMULATOR_OPERATION_TIMEOUT_SECONDS:-180}"

  echo "Shutting down migrated simulator $simulator_id for UI-test cloning..."
  if ! run_with_timeout "$timeout_seconds" xcrun simctl shutdown "$simulator_id"; then
    echo "::error::Simulator $simulator_id did not shut down within ${timeout_seconds}s." >&2
    return 1
  fi
}

run_ui_test_on_clone() {
  local base_simulator_id="$1"
  local test="$2"
  local index="$3"
  local shard_attempts="${PINES_XCODE_UI_SHARD_ATTEMPTS:-}"

  if [ -z "$shard_attempts" ]; then
    if [ "${CI:-}" = "true" ]; then
      shard_attempts=2
    else
      shard_attempts=1
    fi
  fi
  if ! [[ "$shard_attempts" =~ ^[1-9][0-9]*$ ]]; then
    echo "::error::PINES_XCODE_UI_SHARD_ATTEMPTS must be a positive integer." >&2
    return 2
  fi

  local attempt
  local status=0
  for ((attempt = 1; attempt <= shard_attempts; attempt++)); do
    status=0
    run_ui_test_clone_attempt "$base_simulator_id" "$test" "$index" "$attempt" || status=$?
    if [ "$status" -eq 0 ]; then
      return 0
    fi

    if [ "$attempt" -lt "$shard_attempts" ]; then
      echo "::warning::UI smoke ${test##*/} failed on clone attempt $attempt (status $status); retrying on a fresh clone." >&2
    fi
  done

  echo "::error::UI smoke ${test##*/} failed across $shard_attempts fresh simulator clone attempt(s) (last status $status)." >&2
  return "$status"
}

run_ui_test_clone_attempt() {
  local base_simulator_id="$1"
  local test="$2"
  local index="$3"
  local attempt="$4"
  local timeout_seconds="${PINES_SIMULATOR_OPERATION_TIMEOUT_SECONDS:-180}"
  local clone_name
  clone_name="Pines-CI-UI-$$-$index-$attempt-$(date +%s)"

  echo "Cloning migrated simulator $base_simulator_id for ${test##*/} (attempt $attempt)..."
  ui_test_simulator_id=""
  if ! ui_test_simulator_id="$(run_with_timeout "$timeout_seconds" \
    xcrun simctl clone "$base_simulator_id" "$clone_name")"; then
    echo "::warning::Unable to clone simulator $base_simulator_id for ${test##*/} attempt $attempt." >&2
    return 1
  fi

  if ! run_with_timeout "$timeout_seconds" xcrun simctl boot "$ui_test_simulator_id"; then
    echo "::warning::UI-test clone $ui_test_simulator_id did not boot within ${timeout_seconds}s." >&2
    cleanup_ui_test_simulator
    return 1
  fi
  if ! run_with_timeout "$timeout_seconds" xcrun simctl bootstatus "$ui_test_simulator_id" -b; then
    echo "::warning::UI-test clone $ui_test_simulator_id did not finish booting within ${timeout_seconds}s." >&2
    xcrun simctl diagnose -b --no-archive || true
    cleanup_ui_test_simulator
    return 1
  fi

  local status=0
  PINES_XCODE_TEST_FAILURE_ANNOTATION=warning run_xcode_test_phase \
    "$ui_test_simulator_id" \
    "UI smoke: ${test##*/}" \
    "-only-testing:$test" || status=$?
  cleanup_ui_test_simulator
  return "$status"
}

cleanup_ui_test_simulator() {
  [ -n "$ui_test_simulator_id" ] || return 0
  local timeout_seconds="${PINES_SIMULATOR_OPERATION_TIMEOUT_SECONDS:-180}"
  echo "Cleaning up UI-test simulator $ui_test_simulator_id..."
  run_with_timeout "$timeout_seconds" xcrun simctl shutdown "$ui_test_simulator_id" >/dev/null 2>&1 || true
  run_with_timeout "$timeout_seconds" xcrun simctl delete "$ui_test_simulator_id" >/dev/null 2>&1 || true
  ui_test_simulator_id=""
}

cleanup_test_simulator() {
  [ "${CI:-}" = "true" ] || return 0
  cleanup_ui_test_simulator
  [ -f "$simulator_id_file" ] || return 0
  local simulator_id
  simulator_id="$(cat "$simulator_id_file")"
  [ -n "$simulator_id" ] || return 0
  local timeout_seconds="${PINES_SIMULATOR_OPERATION_TIMEOUT_SECONDS:-180}"
  echo "Cleaning up validation simulator $simulator_id..."
  run_with_timeout "$timeout_seconds" xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
  run_with_timeout "$timeout_seconds" xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || true
  rm -f "$simulator_id_file"
}

run_with_timeout() {
  local timeout_seconds="$1"
  shift

  if [ "$timeout_seconds" -le 0 ]; then
    "$@"
    return
  fi

  perl -e '
    my $timeout = shift @ARGV;
    alarm $timeout;
    exec @ARGV or die "exec failed: $!\n";
  ' "$timeout_seconds" "$@"
}

finalize_validation() {
  cleanup_test_simulator
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

main() {
  local command="${1:-all}"
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
      return 2
      ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
