#!/usr/bin/env bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

echo "Checking Xcode workflow runtime contracts..."
ruby scripts/ci/check-xcode-workflow-contracts.rb

echo "Xcode workflow runtime contracts passed."
