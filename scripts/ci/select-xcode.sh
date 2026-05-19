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

  selected="$xcode"

  if metal="$(find_developer_tool metal)"; then
    selected_metal="$metal"
  else
    echo "Warning: xcrun cannot find the Metal compiler for $xcode." >&2
  fi

  if metallib="$(find_developer_tool metallib)"; then
    selected_metallib="$metallib"
  else
    echo "Warning: xcrun cannot find metallib for $xcode." >&2
  fi

  break
done

if [ -z "$selected" ]; then
  echo "No installed Xcode with an iPhoneOS SDK was found." >&2
  exit 1
fi

echo "Selected $selected"
xcodebuild -version
xcodebuild -showsdks

if [ -n "$selected_metal" ]; then
  echo "metal: $selected_metal"
else
  echo "metal: not found by xcrun during Xcode selection"
fi

if [ -n "$selected_metallib" ]; then
  echo "metallib: $selected_metallib"
else
  echo "metallib: not found by xcrun during Xcode selection"
fi

if [ -n "${GITHUB_ENV:-}" ]; then
  echo "DEVELOPER_DIR=$selected/Contents/Developer" >>"$GITHUB_ENV"
  if [ -n "$selected_metal" ]; then
    echo "PINES_METAL_PATH=$selected_metal" >>"$GITHUB_ENV"
  fi
  if [ -n "$selected_metallib" ]; then
    echo "PINES_METALLIB_PATH=$selected_metallib" >>"$GITHUB_ENV"
  fi
fi
