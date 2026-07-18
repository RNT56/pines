#!/usr/bin/env bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

# The repository-wide ShellCheck invocation does not follow sourced files.
# shellcheck disable=SC1091
source scripts/ci/run-xcode-validation.sh

calls=0
# Invoked indirectly by run_ui_test_on_clone from the sourced validation script.
# shellcheck disable=SC2329
run_ui_test_clone_attempt() {
  calls=$((calls + 1))
  [ "$calls" -ge 2 ]
}

PINES_XCODE_UI_SHARD_ATTEMPTS=2 run_ui_test_on_clone base-id PinesUITests/PinesUITests/testRetry 1 >/dev/null 2>&1
if [ "$calls" -ne 2 ]; then
  echo "Expected a failed UI shard to retry exactly once on a fresh clone." >&2
  exit 1
fi

calls=0
run_ui_test_clone_attempt() {
  calls=$((calls + 1))
  return 65
}

status=0
PINES_XCODE_UI_SHARD_ATTEMPTS=2 run_ui_test_on_clone base-id PinesUITests/PinesUITests/testFailure 1 >/dev/null 2>&1 || status=$?
if [ "$status" -ne 65 ] || [ "$calls" -ne 2 ]; then
  echo "Expected a deterministic UI shard failure to fail after two fresh clones." >&2
  exit 1
fi

status=0
PINES_XCODE_UI_SHARD_ATTEMPTS=0 run_ui_test_on_clone base-id PinesUITests/PinesUITests/testInvalid 1 >/dev/null 2>&1 || status=$?
if [ "$status" -ne 2 ]; then
  echo "Expected invalid UI shard retry configuration to fail validation." >&2
  exit 1
fi

echo "Xcode UI shard retry tests passed."
