#!/usr/bin/env bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
project_yml="${PINES_PROJECT_YML:-$root/project.yml}"
project="${PINES_XCODE_PROJECT:-$root/Pines.xcodeproj}"
performance_scheme="${PINES_PERFORMANCE_SCHEME:-PinesPerformance}"
settings_scheme="${PINES_RELEASE_SETTINGS_SCHEME:-Pines}"
target="${PINES_RELEASE_TARGET:-Pines}"
configuration="${PINES_RELEASE_CONFIGURATION:-Release}"

usage() {
  cat <<'USAGE'
usage: check-release-build-hygiene.sh [project|settings|binary <mach-o>|all [mach-o]]

project   Validate the declarative project, generated schemes, and production dependencies.
settings  Resolve and validate the production Pines Release build settings.
binary    Reject coverage sections and debug benchmark-helper leakage in a supplied Mach-O.
all       Run project and settings checks, plus the binary check when a path is supplied.

Set PINES_BUILD_SETTINGS_JSON to validate a previously captured xcodebuild
-showBuildSettings -json result without invoking xcodebuild.
USAGE
}

fail() {
  echo "Release build hygiene check failed: $1" >&2
  exit 1
}

check_project() {
  [ -f "$project_yml" ] || fail "missing declarative project at $project_yml"
  [ -f "$project/project.pbxproj" ] || fail "missing generated project at $project"

  python3 - "$project_yml" "$project" "$performance_scheme" <<'PY'
import pathlib
import sys
import xml.etree.ElementTree as ET

project_yml = pathlib.Path(sys.argv[1])
project = pathlib.Path(sys.argv[2])
scheme_name = sys.argv[3]
lines = project_yml.read_text(encoding="utf-8").splitlines()


def fail(message: str) -> None:
    raise SystemExit(f"Release build hygiene check failed: {message}")


def key_range(key, indent, start=0, end=None):
    if end is None:
        end = len(lines)
    prefix = " " * indent + key + ":"
    for index in range(start, end):
        raw = lines[index]
        if raw == prefix or raw.startswith(prefix + " "):
            block_end = index + 1
            while block_end < end:
                candidate = lines[block_end]
                if candidate.strip() and not candidate.lstrip().startswith("#"):
                    candidate_indent = len(candidate) - len(candidate.lstrip(" "))
                    if candidate_indent <= indent:
                        break
                block_end += 1
            return index, block_end
    fail(f"project.yml is missing {' / '.join([key])}")


settings_start, settings_end = key_range("settings", 0)
configs_start, configs_end = key_range("configs", 2, settings_start + 1, settings_end)
release_start, release_end = key_range("Release", 4, configs_start + 1, configs_end)
coverage = None
for raw in lines[release_start + 1:release_end]:
    stripped = raw.strip()
    if stripped.startswith("ENABLE_CODE_COVERAGE:"):
        coverage = stripped.split(":", 1)[1].strip().strip('"').upper()
        break
if coverage != "NO":
    fail("project.yml must set settings.configs.Release.ENABLE_CODE_COVERAGE to NO")

targets_start, targets_end = key_range("targets", 0)
pines_start, pines_end = key_range("Pines", 2, targets_start + 1, targets_end)
pines_block = "\n".join(lines[pines_start:pines_end])
for product in ("TurboQuantBench", "IntegrationTestHelpers"):
    if f"product: {product}" in pines_block:
        fail(f"production Pines target still depends on {product}")

pbxproj = (project / "project.pbxproj").read_text(encoding="utf-8")
for product in ("TurboQuantBench", "IntegrationTestHelpers"):
    if f"productName = {product};" in pbxproj:
        fail(f"generated project still contains the debug-only product {product}")
if "ENABLE_CODE_COVERAGE = NO;" not in pbxproj:
    fail("generated project does not contain the explicit Release coverage setting")

performance_scheme = project / "xcshareddata" / "xcschemes" / f"{scheme_name}.xcscheme"
default_scheme = project / "xcshareddata" / "xcschemes" / "Pines.xcscheme"
for path in (performance_scheme, default_scheme):
    if not path.is_file():
        fail(f"missing generated shared scheme {path}")

performance_root = ET.parse(performance_scheme).getroot()
for action_name in ("TestAction", "LaunchAction", "ProfileAction", "AnalyzeAction", "ArchiveAction"):
    action = performance_root.find(action_name)
    if action is None or action.get("buildConfiguration") != "Release":
        fail(f"{scheme_name} {action_name} must resolve Release")
performance_test_action = performance_root.find("TestAction")
if performance_test_action is not None and performance_test_action.get("codeCoverageEnabled") == "YES":
    fail(f"{scheme_name} must not gather coverage")

build_entry = None
for entry in performance_root.findall("./BuildAction/BuildActionEntries/BuildActionEntry"):
    reference = entry.find("BuildableReference")
    if reference is not None and reference.get("BlueprintName") == "Pines":
        build_entry = entry
        break
if build_entry is None:
    fail(f"{scheme_name} does not build the Pines app target")
for attribute in ("buildForRunning", "buildForProfiling", "buildForArchiving", "buildForAnalyzing"):
    if build_entry.get(attribute) != "YES":
        fail(f"{scheme_name} Pines build entry must enable {attribute}")

default_root = ET.parse(default_scheme).getroot()
test_action = default_root.find("TestAction")
if (
    test_action is None
    or test_action.get("buildConfiguration") != "Debug"
    or test_action.get("codeCoverageEnabled") != "YES"
):
    fail("Pines Debug tests must continue to gather coverage")
for action_name in ("ProfileAction", "ArchiveAction"):
    action = default_root.find(action_name)
    if action is None or action.get("buildConfiguration") != "Release":
        fail(f"Pines {action_name} must resolve Release")
PY

  echo "Release project hygiene passed."
}

check_settings() {
  local settings_json="${PINES_BUILD_SETTINGS_JSON:-}"
  local temporary_settings=""

  if [ -z "$settings_json" ]; then
    temporary_settings="$(mktemp)"
    settings_json="$temporary_settings"
    if ! xcodebuild \
      -project "$project" \
      -scheme "$settings_scheme" \
      -configuration "$configuration" \
      -destination 'generic/platform=iOS' \
      -skipMacroValidation \
      -skipPackagePluginValidation \
      -onlyUsePackageVersionsFromResolvedFile \
      -disableAutomaticPackageResolution \
      -showBuildSettings \
      -json >"$settings_json"; then
      rm -f "$temporary_settings"
      fail "xcodebuild could not resolve $settings_scheme $configuration settings"
    fi
  fi

  if ! python3 - "$settings_json" "$target" "$configuration" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
target = sys.argv[2]
configuration = sys.argv[3]

try:
    records = json.loads(path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"invalid build settings JSON at {path}: {error}")

record = next((item for item in records if item.get("target") == target), None)
if record is None:
    raise SystemExit(f"build settings do not contain target {target}")

settings = record.get("buildSettings", {})
expected = {
    "CONFIGURATION": configuration,
    "ENABLE_CODE_COVERAGE": "NO",
    "SWIFT_OPTIMIZATION_LEVEL": "-O",
    "SWIFT_COMPILATION_MODE": "wholemodule",
}
for key, value in expected.items():
    actual = settings.get(key)
    if actual != value:
        raise SystemExit(f"{target} {key} resolved {actual!r}, expected {value!r}")

conditions = settings.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "").split()
if "DEBUG" in conditions:
    raise SystemExit(f"{target} Release unexpectedly defines DEBUG")
PY
  then
    rm -f "$temporary_settings"
    fail "$settings_scheme $configuration settings are not production-safe"
  fi

  rm -f "$temporary_settings"
  echo "$settings_scheme Release build settings passed."
}

run_otool() {
  if [ -n "${PINES_OTOOL:-}" ]; then
    "$PINES_OTOOL" "$@"
  else
    xcrun otool "$@"
  fi
}

run_nm() {
  if [ -n "${PINES_NM:-}" ]; then
    "$PINES_NM" "$@"
  else
    xcrun nm "$@"
  fi
}

run_strings() {
  if [ -n "${PINES_STRINGS:-}" ]; then
    "$PINES_STRINGS" "$@"
  else
    /usr/bin/strings "$@"
  fi
}

check_binary() {
  local binary="${1:-}"
  [ -n "$binary" ] || fail "binary mode requires a Mach-O path"
  [ -f "$binary" ] || fail "binary does not exist: $binary"

  local temporary_dir
  temporary_dir="$(mktemp -d)"
  if ! run_otool -l "$binary" >"$temporary_dir/otool.txt" 2>"$temporary_dir/otool.err"; then
    rm -rf "$temporary_dir"
    fail "otool could not inspect the supplied Mach-O: $binary"
  fi

  if grep -E -q '__llvm_(prf|cov)|__LLVM_COV' "$temporary_dir/otool.txt"; then
    rm -rf "$temporary_dir"
    fail "coverage instrumentation sections are present in $binary"
  fi

  run_nm -j "$binary" >"$temporary_dir/nm.txt" 2>/dev/null || true
  if ! run_strings -a "$binary" >"$temporary_dir/strings.txt" 2>"$temporary_dir/strings.err"; then
    rm -rf "$temporary_dir"
    fail "strings could not inspect the supplied Mach-O: $binary"
  fi
  # Match module identities, not legitimate production types such as
  # TurboQuantBenchmarkReport or TurboQuantBenchmarkSuiteID.
  local helper_module_pattern
  helper_module_pattern='[$]s15TurboQuantBench|[$]s22IntegrationTestHelpers|(^|[/._-])(TurboQuantBench|IntegrationTestHelpers)($|[/._-])'
  if grep -E -q "$helper_module_pattern" \
    "$temporary_dir/nm.txt" "$temporary_dir/strings.txt"; then
    rm -rf "$temporary_dir"
    fail "debug benchmark-helper symbols or strings leaked into $binary"
  fi

  rm -rf "$temporary_dir"
  echo "Release Mach-O hygiene passed: $binary"
}

mode="${1:-all}"
case "$mode" in
  project)
    [ "$#" -eq 1 ] || { usage >&2; exit 2; }
    check_project
    ;;
  settings)
    [ "$#" -eq 1 ] || { usage >&2; exit 2; }
    check_settings
    ;;
  binary)
    [ "$#" -eq 2 ] || { usage >&2; exit 2; }
    check_binary "$2"
    ;;
  all)
    [ "$#" -le 2 ] || { usage >&2; exit 2; }
    check_project
    check_settings
    if [ "$#" -eq 2 ]; then
      check_binary "$2"
    fi
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
