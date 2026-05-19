#!/usr/bin/env bash
set -euo pipefail

without_codeql_tracer() {
  env -u DYLD_INSERT_LIBRARIES -u SEMMLE_PRELOAD_libtrace "$@"
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
    xcrun -sdk macosx -find "$tool" 2>/dev/null
}

escape_replacement() {
  printf '%s' "$1" | sed 's/[&/\]/\\&/g'
}

metal_path="$(find_developer_tool metal "${PINES_METAL_PATH:-}")"
metallib_path="$(find_developer_tool metallib "${PINES_METALLIB_PATH:-}")"

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
