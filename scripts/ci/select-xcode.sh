#!/usr/bin/env bash
set -euo pipefail

select_xcode() {
  local xcode="$1"
  if [ "${CI:-}" = "true" ]; then
    sudo xcode-select -s "$xcode"
  else
    xcode-select -s "$xcode"
  fi
}

without_codeql_tracer() {
  env -u DYLD_INSERT_LIBRARIES -u SEMMLE_PRELOAD_libtrace "$@"
}

find_developer_tool() {
  local tool="$1"

  without_codeql_tracer xcrun -sdk macosx -find "$tool" 2>/dev/null ||
    xcrun -sdk macosx -find "$tool" 2>/dev/null
}

selected=""
selected_metal=""
selected_metallib=""

for xcode in /Applications/Xcode*.app; do
  [ -d "$xcode" ] || continue
  select_xcode "$xcode"

  if ! xcodebuild -showsdks | grep -qi 'iphoneos'; then
    echo "Skipping $xcode because it does not expose an iPhoneOS SDK." >&2
    continue
  fi

  if ! metal="$(find_developer_tool metal)"; then
    echo "Skipping $xcode because xcrun cannot find the Metal compiler." >&2
    continue
  fi

  if ! metallib="$(find_developer_tool metallib)"; then
    echo "Skipping $xcode because xcrun cannot find metallib." >&2
    continue
  fi

  selected="$xcode"
  selected_metal="$metal"
  selected_metallib="$metallib"
  break
done

if [ -z "$selected" ]; then
  echo "No installed Xcode with an iPhoneOS SDK and Metal command-line tools was found." >&2
  exit 1
fi

echo "Selected $selected"
xcodebuild -version
xcodebuild -showsdks
echo "metal: $selected_metal"
echo "metallib: $selected_metallib"

if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "DEVELOPER_DIR=$selected/Contents/Developer"
    echo "PINES_METAL_PATH=$selected_metal"
    echo "PINES_METALLIB_PATH=$selected_metallib"
  } >>"$GITHUB_ENV"
fi
