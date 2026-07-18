#!/usr/bin/env bash
set -euo pipefail

select_xcode() {
  local xcode="$1"
  local developer_dir="$xcode/Contents/Developer"
  if [ "$(xcode-select -p 2>/dev/null || true)" = "$developer_dir" ]; then
    return 0
  fi
  if [ "${CI:-}" = "true" ]; then
    sudo xcode-select -s "$xcode"
  else
    xcode-select -s "$xcode"
  fi
}

without_codeql_tracer() {
  env -u DYLD_INSERT_LIBRARIES -u SEMMLE_PRELOAD_libtrace "$@"
}

xcode_candidates() {
  local applications_dir="${PINES_XCODE_APPLICATIONS_DIR:-/Applications}"
  local override="${PINES_XCODE_PATH:-}"
  local default_xcode="$applications_dir/Xcode.app"
  local LC_ALL=C

  if [ -n "$override" ]; then
    if [ ! -d "$override" ]; then
      echo "Configured PINES_XCODE_PATH does not exist: $override" >&2
      return 1
    fi
    printf '%s\n' "$override"
    return 0
  fi

  # GitHub's macOS images keep Xcode.app pointed at the current stable Xcode.
  # Prefer that maintained default before the versioned installs: a normal
  # lexicographic Xcode*.app glob starts at Xcode_26.0.1.app and silently pins
  # CI to the oldest available Xcode instead.
  if [ -d "$default_xcode" ]; then
    printf '%s\n' "$default_xcode"
  fi

  local stable=()
  local prerelease=()
  local xcode
  local name
  for xcode in "$applications_dir"/Xcode*.app; do
    [ -d "$xcode" ] || continue
    [ "$xcode" = "$default_xcode" ] && continue
    name="${xcode##*/}"
    case "$name" in
      *[Bb][Ee][Tt][Aa]*|*[Rr][Cc]*) prerelease+=("$xcode") ;;
      *) stable+=("$xcode") ;;
    esac
  done

  local index
  for ((index = ${#stable[@]} - 1; index >= 0; index--)); do
    printf '%s\n' "${stable[$index]}"
  done
  for ((index = ${#prerelease[@]} - 1; index >= 0; index--)); do
    printf '%s\n' "${prerelease[$index]}"
  done
}

find_developer_tool() {
  local xcode="$1"
  local tool="$2"
  local developer_dir="$xcode/Contents/Developer"

  without_codeql_tracer env DEVELOPER_DIR="$developer_dir" xcrun -sdk macosx -find "$tool" 2>/dev/null ||
    env DEVELOPER_DIR="$developer_dir" xcrun -sdk macosx -find "$tool" 2>/dev/null
}

main() {
  local selected=""
  local selected_metal=""
  local selected_metallib=""
  local xcode

  while IFS= read -r xcode; do
    [ -d "$xcode" ] || continue
    local developer_dir="$xcode/Contents/Developer"

    if ! env DEVELOPER_DIR="$developer_dir" xcodebuild -showsdks | grep -qi 'iphoneos'; then
      echo "Skipping $xcode because it does not expose an iPhoneOS SDK." >&2
      continue
    fi

    selected="$xcode"

    if metal="$(find_developer_tool "$xcode" metal)"; then
      selected_metal="$metal"
    else
      echo "Warning: xcrun cannot find the Metal compiler for $xcode." >&2
    fi

    if metallib="$(find_developer_tool "$xcode" metallib)"; then
      selected_metallib="$metallib"
    else
      echo "Warning: xcrun cannot find metallib for $xcode." >&2
    fi

    break
  done < <(xcode_candidates)

  if [ -z "$selected" ]; then
    echo "No installed Xcode with an iPhoneOS SDK was found." >&2
    return 1
  fi

  select_xcode "$selected"

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
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
