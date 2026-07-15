#!/usr/bin/env bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
checker="$root/scripts/ci/check-release-build-hygiene.sh"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

fail() {
  echo "Release build hygiene self-test failed: $1" >&2
  exit 1
}

expect_failure() {
  if "$@" >"$temporary_dir/expected-failure.out" 2>&1; then
    fail "command unexpectedly passed: $*"
  fi
}

write_settings() {
  local path="$1"
  local coverage="$2"
  cat >"$path" <<JSON
[
  {
    "target": "Pines",
    "buildSettings": {
      "CONFIGURATION": "Release",
      "ENABLE_CODE_COVERAGE": "$coverage",
      "SWIFT_OPTIMIZATION_LEVEL": "-O",
      "SWIFT_COMPILATION_MODE": "wholemodule",
      "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ""
    }
  }
]
JSON
}

cat >"$temporary_dir/otool" <<'SH'
#!/usr/bin/env bash
cat "${PINES_TEST_OTOOL_OUTPUT:?}"
SH
cat >"$temporary_dir/nm" <<'SH'
#!/usr/bin/env bash
cat "${PINES_TEST_NM_OUTPUT:?}"
SH
cat >"$temporary_dir/strings" <<'SH'
#!/usr/bin/env bash
cat "${PINES_TEST_STRINGS_OUTPUT:?}"
SH
chmod +x "$temporary_dir/otool" "$temporary_dir/nm" "$temporary_dir/strings"

touch "$temporary_dir/app-binary" "$temporary_dir/clean-nm" "$temporary_dir/clean-strings"
printf 'Load command 0\n      segname __TEXT\n' >"$temporary_dir/clean-otool"
printf 'Load command 0\n      sectname __llvm_prf_cnts\n' >"$temporary_dir/coverage-otool"
printf "_\$s15TurboQuantBench0aB0O3runyyF\n" >"$temporary_dir/helper-nm"

bash "$checker" project >/dev/null

write_settings "$temporary_dir/good-settings.json" NO
PINES_BUILD_SETTINGS_JSON="$temporary_dir/good-settings.json" \
  bash "$checker" settings >/dev/null
write_settings "$temporary_dir/bad-settings.json" YES
expect_failure env PINES_BUILD_SETTINGS_JSON="$temporary_dir/bad-settings.json" \
  bash "$checker" settings

binary_environment=(
  PINES_OTOOL="$temporary_dir/otool"
  PINES_NM="$temporary_dir/nm"
  PINES_STRINGS="$temporary_dir/strings"
  PINES_TEST_NM_OUTPUT="$temporary_dir/clean-nm"
  PINES_TEST_STRINGS_OUTPUT="$temporary_dir/clean-strings"
)
env "${binary_environment[@]}" \
  PINES_TEST_OTOOL_OUTPUT="$temporary_dir/clean-otool" \
  bash "$checker" binary "$temporary_dir/app-binary" >/dev/null
expect_failure env "${binary_environment[@]}" \
  PINES_TEST_OTOOL_OUTPUT="$temporary_dir/coverage-otool" \
  bash "$checker" binary "$temporary_dir/app-binary"
expect_failure env "${binary_environment[@]}" \
  PINES_TEST_OTOOL_OUTPUT="$temporary_dir/clean-otool" \
  PINES_TEST_NM_OUTPUT="$temporary_dir/helper-nm" \
  bash "$checker" binary "$temporary_dir/app-binary"

echo "Release build hygiene self-tests passed."
