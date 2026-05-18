#!/usr/bin/env bash
set -euo pipefail

project="${PINES_XCODE_PROJECT:-Pines.xcodeproj}"
scheme="${PINES_XCODE_SCHEME:-Pines}"
xcode_package_flags=(
  -skipMacroValidation
  -skipPackagePluginValidation
  -onlyUsePackageVersionsFromResolvedFile
  -disableAutomaticPackageResolution
)

run_xcodebuild_admin() {
  if [ "${CI:-}" = "true" ]; then
    sudo xcodebuild "$@"
  else
    xcodebuild "$@"
  fi
}

if [ "${CI:-}" = "true" ]; then
  run_xcodebuild_admin -runFirstLaunch -checkForNewerComponents || true
else
  xcodebuild -runFirstLaunch >/dev/null 2>&1 || true
fi

destination_is_available() {
  local scheme_name="$1"
  local destination="$2"
  local label="$3"
  local output
  output="$(mktemp "${TMPDIR:-/tmp}/pines-destinations.XXXXXX")"

  if ! xcodebuild \
    -project "$project" \
    -scheme "$scheme_name" \
    -destination "$destination" \
    "${xcode_package_flags[@]}" \
    -showdestinations >"$output" 2>&1; then
    echo "$label destination check failed:"
    sed -n '1,120p' "$output"
    rm -f "$output"
    return 1
  fi

  if grep -Eiq 'Ineligible destinations|not installed|unavailable|Unable to find a destination' "$output"; then
    echo "$label destination is not ready:"
    sed -n '1,160p' "$output"
    rm -f "$output"
    return 1
  fi

  echo "$label destination is available."
  rm -f "$output"
  return 0
}

download_platform() {
  local platform="$1"
  local scheme_name="$2"

  xcrun simctl list >/dev/null 2>&1 || true

  for attempt in 1 2; do
    echo "Installing or refreshing $platform platform for the $scheme_name Xcode scheme (attempt $attempt)..."
    if run_xcodebuild_admin -downloadPlatform "$platform" -architectureVariant universal; then
      return 0
    fi

    xcrun simctl list >/dev/null 2>&1 || true
    sleep 10
  done

  return 1
}

ensure_platform() {
  local platform="$1"
  local sdk_identifier="$2"
  local scheme_name="$3"
  local destination="$4"
  local should_download=0

  if [ "${PINES_FORCE_PLATFORM_DOWNLOAD:-0}" = "1" ]; then
    should_download=1
  elif ! xcodebuild -showsdks | grep -qi "$sdk_identifier"; then
    should_download=1
  elif ! destination_is_available "$scheme_name" "$destination" "$platform"; then
    should_download=1
  fi

  if [ "$should_download" = "1" ]; then
    if ! download_platform "$platform" "$scheme_name"; then
      echo "::error::xcodebuild could not download the $platform platform required by the $scheme_name scheme." >&2
      xcodebuild -showsdks || true
      exit 1
    fi
  else
    echo "$platform SDK is already visible to xcodebuild."
  fi

  if ! xcodebuild -showsdks | grep -qi "$sdk_identifier"; then
    echo "::error::$platform platform is required by the Pines scheme but is still unavailable after installation." >&2
    xcodebuild -showsdks || true
    exit 1
  fi

  if ! destination_is_available "$scheme_name" "$destination" "$platform"; then
    echo "::error::$platform platform is required by the $scheme_name scheme but its build destination is unavailable." >&2
    exit 1
  fi
}

ensure_platform iOS iphoneos "$scheme" 'generic/platform=iOS'
ensure_platform watchOS watchos PinesWatch 'generic/platform=watchOS'

xcodebuild -showsdks
