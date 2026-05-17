#!/usr/bin/env bash
set -euo pipefail

project="${PINES_XCODE_PROJECT:-Pines.xcodeproj}"
scheme="${PINES_XCODE_SCHEME:-Pines}"
derived_data="${PINES_DERIVED_DATA_PATH:-build/DerivedData}"

mkdir -p build

generated_project_snapshot="$(mktemp -d "${TMPDIR:-/tmp}/pines-xcodegen-before.XXXXXX")"
trap 'rm -rf "$generated_project_snapshot"' EXIT

snapshot_generated_project() {
  if [ -e "$project" ]; then
    mkdir -p "$generated_project_snapshot/project"
    rsync -a \
      --exclude 'xcuserdata/' \
      --exclude '*.xcuserstate' \
      "$project/" "$generated_project_snapshot/project/"
  else
    touch "$generated_project_snapshot/project-missing"
  fi
}

check_generated_project_drift() {
  echo "Checking generated project drift..."
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

snapshot_generated_project

echo "Generating Xcode project..."
xcodegen generate

echo "Resolving Xcode package dependencies..."
xcodebuild \
  -resolvePackageDependencies \
  -project "$project" \
  -scheme "$scheme" \
  -skipMacroValidation \
  -skipPackagePluginValidation

echo "Building iOS app without signing..."
set -o pipefail
xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$derived_data" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  build | tee build/xcodebuild.log

echo "Building iOS runtime smoke tests..."
xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived_data" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing | tee build/xcodebuild-tests.log

if [ "${PINES_SKIP_SIMULATOR_TEST_RUN:-0}" = "1" ]; then
  echo "Skipping simulator test run because PINES_SKIP_SIMULATOR_TEST_RUN=1."
  check_generated_project_drift
  exit 0
fi

simulator_id="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }')"
if [ -z "$simulator_id" ]; then
  echo "::warning::No available iPhone simulator was found; smoke tests were build-verified only."
  check_generated_project_drift
  exit 0
fi

echo "Running iOS runtime smoke tests..."
xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -destination "id=$simulator_id" \
  -derivedDataPath "$derived_data" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  test-without-building | tee build/xcodebuild-test-run.log

check_generated_project_drift
