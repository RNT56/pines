#!/usr/bin/env bash
set -euo pipefail

MLX_SWIFT_REPO="${MLX_SWIFT_REPO:-https://github.com/RNT56/mlx-swift}"
MLX_SWIFT_LM_REPO="${MLX_SWIFT_LM_REPO:-https://github.com/RNT56/mlx-swift-lm}"
MLX_SWIFT_REVISION="${MLX_SWIFT_REVISION:-}"
MLX_SWIFT_LM_REVISION="${MLX_SWIFT_LM_REVISION:-}"
RUN_BUILD=0
RUN_TESTS=0
CHECK_ONLY=0

usage() {
  cat <<'USAGE'
Usage: tools/update-mlx-pins.sh [options]

Updates the reproducible MLX fork revisions in project.yml, regenerates
Pines.xcodeproj with XcodeGen, and verifies the package pin guard.

Options:
  --mlx-swift SHA       Pin RNT56/mlx-swift to SHA. Defaults to remote HEAD.
  --mlx-swift-lm SHA    Pin RNT56/mlx-swift-lm to SHA. Defaults to remote HEAD.
  --build              Also build the iOS app without signing.
  --test               Also run Swift package tests and iOS smoke tests.
  --check-only         Resolve latest revisions and print them without editing.
  -h, --help           Show this help.

Environment:
  MLX_SWIFT_REPO       Override the mlx-swift fork URL.
  MLX_SWIFT_LM_REPO    Override the mlx-swift-lm fork URL.
  MLX_SWIFT_REVISION   Override the mlx-swift revision.
  MLX_SWIFT_LM_REVISION
                       Override the mlx-swift-lm revision.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mlx-swift)
      MLX_SWIFT_REVISION="${2:-}"
      shift 2
      ;;
    --mlx-swift-lm)
      MLX_SWIFT_LM_REVISION="${2:-}"
      shift 2
      ;;
    --build)
      RUN_BUILD=1
      shift
      ;;
    --test)
      RUN_TESTS=1
      shift
      ;;
    --check-only)
      CHECK_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

latest_head() {
  local repo="$1"
  git ls-remote "$repo" HEAD | awk 'NR == 1 { print $1 }'
}

require_sha() {
  local name="$1"
  local revision="$2"
  if [[ ! "$revision" =~ ^[0-9a-f]{40}$ ]]; then
    echo "$name resolved to an invalid revision: $revision" >&2
    exit 1
  fi
}

rewrite_project_yml() {
  export MLX_SWIFT_REVISION MLX_SWIFT_LM_REVISION
  perl -0pi -e '
    s{(MLXSwift:\n\s+url:\s+https://github\.com/RNT56/mlx-swift\n\s+revision:\s+)[0-9a-f]{40}}{$1 . $ENV{MLX_SWIFT_REVISION}}e
  ' project.yml
  perl -0pi -e '
    s{(MLXSwiftLM:\n\s+url:\s+https://github\.com/RNT56/mlx-swift-lm\n\s+revision:\s+)[0-9a-f]{40}}{$1 . $ENV{MLX_SWIFT_LM_REVISION}}e
  ' project.yml
}

MLX_SWIFT_REVISION="${MLX_SWIFT_REVISION:-$(latest_head "$MLX_SWIFT_REPO")}"
MLX_SWIFT_LM_REVISION="${MLX_SWIFT_LM_REVISION:-$(latest_head "$MLX_SWIFT_LM_REPO")}"
require_sha "mlx-swift" "$MLX_SWIFT_REVISION"
require_sha "mlx-swift-lm" "$MLX_SWIFT_LM_REVISION"

echo "mlx-swift:    $MLX_SWIFT_REVISION"
echo "mlx-swift-lm: $MLX_SWIFT_LM_REVISION"

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  exit 0
fi

rewrite_project_yml

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required to regenerate Pines.xcodeproj." >&2
  exit 1
fi
xcodegen generate

bash scripts/ci/check-mlx-package-pins.sh

if [[ "$RUN_TESTS" -eq 1 ]]; then
  swift test
  swift run PinesCoreTestRunner
fi

if [[ "$RUN_BUILD" -eq 1 ]]; then
  xcodebuild \
    -project Pines.xcodeproj \
    -scheme Pines \
    -destination 'generic/platform=iOS' \
    -derivedDataPath /tmp/PinesDerivedDataMLXPins \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO \
    build
fi

if [[ "$RUN_TESTS" -eq 1 ]]; then
  xcodebuild \
    -project Pines.xcodeproj \
    -scheme Pines \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath /tmp/PinesDerivedDataMLXPins \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO \
    build-for-testing

  simulator_id="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }')"
  if [[ -z "$simulator_id" ]]; then
    echo "No available iPhone simulator was found; iOS smoke tests were build-verified only." >&2
    exit 0
  fi

  xcodebuild \
    -project Pines.xcodeproj \
    -scheme Pines \
    -destination "id=$simulator_id" \
    -derivedDataPath /tmp/PinesDerivedDataMLXPins \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO \
    test-without-building
fi
