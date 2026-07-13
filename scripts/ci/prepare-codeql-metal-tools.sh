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

require_mlx_helper() {
  local required="${PINES_REQUIRE_CODEQL_METAL_PATCH:-}"
  [ "$required" = "1" ] || [ "$required" = "true" ]
}

if ! metal_path="$(find_developer_tool metal "${PINES_METAL_PATH:-}")"; then
  echo "Unable to locate the Metal compiler for CodeQL tracing." >&2
  exit 1
fi

if ! metallib_path="$(find_developer_tool metallib "${PINES_METALLIB_PATH:-}")"; then
  echo "Unable to locate metallib for CodeQL tracing." >&2
  exit 1
fi

script="${PINES_CODEQL_MLX_HELPER:-build/DerivedData/SourcePackages/checkouts/mlx-swift/tools/build-swiftpm-metallib.sh}"
if [ ! -f "$script" ]; then
  if require_mlx_helper; then
    echo "MLX SwiftPM Metal helper was not found; resolve Xcode packages into build/DerivedData before CodeQL build." >&2
    exit 1
  fi

  echo "MLX SwiftPM Metal helper was not found; no CodeQL Metal patch is needed."
  exit 0
fi

# MLX Swift used a fixed macOS SDK in older helpers and now derives the SDK
# from the active Apple platform. Patch either form so CodeQL's injected
# tracer never has to discover the separately installed Metal toolchain.
METAL_REPLACEMENT="$metal_path" perl -0pi -e '
  s{METAL=\$\(xcrun -sdk (?:macosx|"\$\{sdk\}") -find metal\)}{METAL="$ENV{METAL_REPLACEMENT}"}g
' "$script"
METALLIB_REPLACEMENT="$metallib_path" perl -0pi -e '
  s{METALLIB=\$\(xcrun -sdk (?:macosx|"\$\{sdk\}") -find metallib\)}{METALLIB="$ENV{METALLIB_REPLACEMENT}"}g
' "$script"
perl -0pi -e 's/(?<!SEMMLE_PRELOAD_libtrace )"\$\{METAL\}"/env -u DYLD_INSERT_LIBRARIES -u SEMMLE_PRELOAD_libtrace "\${METAL}"/g' "$script"
perl -0pi -e 's/(?<!SEMMLE_PRELOAD_libtrace )"\$\{METALLIB\}"/env -u DYLD_INSERT_LIBRARIES -u SEMMLE_PRELOAD_libtrace "\${METALLIB}"/g' "$script"

if ! grep -Fq "METAL=\"$metal_path\"" "$script"; then
  echo "Unable to patch the MLX Metal compiler assignment for CodeQL tracing." >&2
  exit 1
fi

if ! grep -Fq "METALLIB=\"$metallib_path\"" "$script"; then
  echo "Unable to patch the MLX metallib assignment for CodeQL tracing." >&2
  exit 1
fi

echo "Prepared MLX SwiftPM Metal helper for CodeQL tracing."
echo "metal: $metal_path"
echo "metallib: $metallib_path"
