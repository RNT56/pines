#!/usr/bin/env bash
set -euo pipefail

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

ensure_platform() {
  local platform="$1"
  local sdk_identifier="$2"
  local should_download=0

  if [ "${CI:-}" = "true" ] || [ "${PINES_FORCE_PLATFORM_DOWNLOAD:-0}" = "1" ]; then
    should_download=1
  elif ! xcodebuild -showsdks | grep -qi "$sdk_identifier"; then
    should_download=1
  fi

  if [ "$should_download" = "1" ]; then
    echo "Installing or refreshing $platform platform for the Pines Xcode scheme..."
    if ! run_xcodebuild_admin -downloadPlatform "$platform" -architectureVariant universal; then
      echo "::error::xcodebuild could not download the $platform platform required by the Pines scheme." >&2
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
}

ensure_platform iOS iphoneos
ensure_platform watchOS watchos

xcodebuild -showsdks
