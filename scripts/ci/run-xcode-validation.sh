#!/usr/bin/env bash
set -euo pipefail

project="${PINES_XCODE_PROJECT:-Pines.xcodeproj}"
scheme="${PINES_XCODE_SCHEME:-Pines}"
derived_data="${PINES_DERIVED_DATA_PATH:-build/DerivedData}"
swiftpm_resolved_file="${PINES_SWIFTPM_PACKAGE_RESOLVED_FILE:-Package.resolved}"
xcode_resolved_file="${PINES_XCODE_PACKAGE_RESOLVED_FILE:-$project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved}"
xcode_package_flags=(
  -skipMacroValidation
  -skipPackagePluginValidation
  -onlyUsePackageVersionsFromResolvedFile
  -disableAutomaticPackageResolution
)

mkdir -p build

generated_project_snapshot="$(mktemp -d "${TMPDIR:-/tmp}/pines-xcodegen-before.XXXXXX")"
trap 'rm -rf "$generated_project_snapshot"' EXIT

snapshot_generated_project() {
  if [ -e "$project" ]; then
    mkdir -p "$generated_project_snapshot/project"
    rsync -a \
      --exclude 'xcuserdata/' \
      --exclude '*.xcuserstate' \
      --exclude 'project.xcworkspace/xcshareddata/swiftpm/configuration/' \
      "$project/" "$generated_project_snapshot/project/"
  else
    touch "$generated_project_snapshot/project-missing"
  fi
}

snapshot_package_resolution_files() {
  if [ ! -f "$swiftpm_resolved_file" ]; then
    echo "::error::$swiftpm_resolved_file is required for deterministic SwiftPM package resolution."
    exit 1
  fi
  if [ ! -f "$xcode_resolved_file" ]; then
    echo "::error::$xcode_resolved_file is required for deterministic Xcode app package resolution."
    exit 1
  fi
  cp "$swiftpm_resolved_file" "$generated_project_snapshot/Package.resolved"
  mkdir -p "$generated_project_snapshot/xcode-swiftpm"
  cp "$xcode_resolved_file" "$generated_project_snapshot/xcode-swiftpm/Package.resolved"
}

check_generated_project_drift() {
  echo "Checking generated project drift..."
  rm -rf "$project/project.xcworkspace/xcshareddata/swiftpm/configuration"
  if [ -e "$generated_project_snapshot/project-missing" ]; then
    if [ -e "$project" ]; then
      echo "::error::$project was generated but is not committed."
      exit 1
    fi
    return 0
  fi

  if ! diff -qr -x xcuserdata -x '*.xcuserstate' "$generated_project_snapshot/project" "$project" >/dev/null; then
    echo "::error::$project changed after xcodegen generate. Commit the generated project updates."
    diff -ru -x xcuserdata -x '*.xcuserstate' "$generated_project_snapshot/project" "$project" || true
    exit 1
  fi
}

check_package_resolution_drift() {
  echo "Checking package resolution drift..."
  if ! cmp -s "$generated_project_snapshot/Package.resolved" "$swiftpm_resolved_file"; then
    echo "::error::$swiftpm_resolved_file changed during Xcode validation. Commit the resolved SwiftPM graph."
    diff -u "$generated_project_snapshot/Package.resolved" "$swiftpm_resolved_file" || true
    exit 1
  fi
  if ! cmp -s "$generated_project_snapshot/xcode-swiftpm/Package.resolved" "$xcode_resolved_file"; then
    echo "::error::$xcode_resolved_file changed during Xcode validation. Commit the resolved Xcode app graph."
    diff -u "$generated_project_snapshot/xcode-swiftpm/Package.resolved" "$xcode_resolved_file" || true
    exit 1
  fi
}

restore_generated_project() {
  echo "Restoring generated Xcode project..."
  xcodegen generate
  check_generated_project_drift
}

snapshot_generated_project
snapshot_package_resolution_files

echo "Generating Xcode project..."
xcodegen generate
check_generated_project_drift

echo "Resolving Xcode package dependencies..."
xcodebuild \
  -resolvePackageDependencies \
  -project "$project" \
  -scheme "$scheme" \
  "${xcode_package_flags[@]}"

echo "Building iOS app without signing..."
set -o pipefail
xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$derived_data" \
  "${xcode_package_flags[@]}" \
  CODE_SIGNING_ALLOWED=NO \
  build | tee build/xcodebuild.log

echo "Building iOS runtime smoke tests..."
xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived_data" \
  "${xcode_package_flags[@]}" \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing | tee build/xcodebuild-tests.log

if [ "${PINES_SKIP_SIMULATOR_TEST_RUN:-0}" = "1" ]; then
  echo "Skipping simulator test run because PINES_SKIP_SIMULATOR_TEST_RUN=1."
  restore_generated_project
  check_package_resolution_drift
  exit 0
fi

simulator_id="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }')"
if [ -z "$simulator_id" ]; then
  echo "::warning::No available iPhone simulator was found; smoke tests were build-verified only."
  restore_generated_project
  check_package_resolution_drift
  exit 0
fi

echo "Running iOS runtime smoke tests..."
xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -destination "id=$simulator_id" \
  -derivedDataPath "$derived_data" \
  "${xcode_package_flags[@]}" \
  CODE_SIGNING_ALLOWED=NO \
  test-without-building | tee build/xcodebuild-test-run.log

restore_generated_project
check_package_resolution_drift
