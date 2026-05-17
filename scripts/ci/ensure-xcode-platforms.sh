#!/usr/bin/env bash
set -euo pipefail

if [ "${CI:-}" = "true" ]; then
  sudo xcodebuild -runFirstLaunch || true
else
  xcodebuild -runFirstLaunch >/dev/null 2>&1 || true
fi

ensure_platform() {
  local platform="$1"
  local sdk_identifier="$2"

  if xcodebuild -showsdks | grep -qi "$sdk_identifier"; then
    echo "$platform platform is already installed."
    return 0
  fi

  echo "Installing $platform platform for the Pines Xcode scheme..."
  if ! xcodebuild -downloadPlatform "$platform" -architectureVariant universal; then
    echo "::error::xcodebuild could not download the $platform platform required by the Pines scheme." >&2
    xcodebuild -showsdks || true
    exit 1
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
