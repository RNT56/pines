#!/usr/bin/env bash
set -euo pipefail

without_codeql_tracer() {
  env -u DYLD_INSERT_LIBRARIES -u SEMMLE_PRELOAD_libtrace "$@"
}

find_tool_in_known_locations() {
  local tool="$1"
  local candidate
  local toolchain_root
  local xcode_root

  if [ -n "${DEVELOPER_DIR:-}" ]; then
    candidate="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/$tool"
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  for toolchain_root in /var/run/com.apple.security.cryptexd/mnt/com.apple.MobileAsset.MetalToolchain-*; do
    candidate="$toolchain_root/Metal.xctoolchain/usr/bin/$tool"
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  for xcode_root in /Applications/Xcode*.app; do
    candidate="$xcode_root/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/$tool"
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  candidate="/Library/Developer/CommandLineTools/usr/bin/$tool"
  if [ -x "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  candidate="/usr/bin/$tool"
  if [ -x "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

find_developer_tool() {
  local tool="$1"
  local configured_path="$2"

  if [ -n "$configured_path" ]; then
    if [ ! -x "$configured_path" ]; then
      echo "Configured $tool path is not executable: $configured_path" >&2
      exit 1
    fi
    printf '%s\n' "$configured_path"
    return 0
  fi

  without_codeql_tracer xcrun -sdk macosx -find "$tool" 2>/dev/null ||
    xcrun -sdk macosx -find "$tool" 2>/dev/null ||
    find_tool_in_known_locations "$tool"
}

escape_replacement() {
  printf '%s' "$1" | sed 's/[&/\]/\\&/g'
}

if ! metal_path="$(find_developer_tool metal "${PINES_METAL_PATH:-}")"; then
  echo "Unable to locate the Metal compiler for CodeQL tracing." >&2
  exit 1
fi

if ! metallib_path="$(find_developer_tool metallib "${PINES_METALLIB_PATH:-}")"; then
  echo "Unable to locate metallib for CodeQL tracing." >&2
  exit 1
fi

script="build/DerivedData/SourcePackages/checkouts/mlx-swift/tools/build-swiftpm-metallib.sh"
if [ ! -f "$script" ]; then
  echo "MLX SwiftPM Metal helper was not found; no CodeQL Metal patch is needed."
  exit 0
fi

metal_replacement="$(escape_replacement "$metal_path")"
metallib_replacement="$(escape_replacement "$metallib_path")"

perl -0pi -e "s/METAL=\\\$\\(xcrun -sdk macosx -find metal\\)/METAL=\"$metal_replacement\"/" "$script"
perl -0pi -e "s/METALLIB=\\\$\\(xcrun -sdk macosx -find metallib\\)/METALLIB=\"$metallib_replacement\"/" "$script"
perl -0pi -e 's/"\$\{METAL\}"/env -u DYLD_INSERT_LIBRARIES -u SEMMLE_PRELOAD_libtrace "\${METAL}"/g' "$script"
perl -0pi -e 's/"\$\{METALLIB\}"/env -u DYLD_INSERT_LIBRARIES -u SEMMLE_PRELOAD_libtrace "\${METALLIB}"/g' "$script"

echo "Prepared MLX SwiftPM Metal helper for CodeQL tracing."
echo "metal: $metal_path"
echo "metallib: $metallib_path"
