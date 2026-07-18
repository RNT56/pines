#!/usr/bin/env bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
# shellcheck source=scripts/ci/select-xcode.sh
source "$root/scripts/ci/select-xcode.sh"

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p \
  "$fixture/Xcode_26.0.1.app" \
  "$fixture/Xcode_26.4.1.app" \
  "$fixture/Xcode_26.5_beta_2.app"
ln -s "$fixture/Xcode_26.4.1.app" "$fixture/Xcode.app"

candidates="$(PINES_XCODE_APPLICATIONS_DIR="$fixture" xcode_candidates)"
expected=$(printf '%s\n' \
  "$fixture/Xcode.app" \
  "$fixture/Xcode_26.4.1.app" \
  "$fixture/Xcode_26.0.1.app" \
  "$fixture/Xcode_26.5_beta_2.app")

if [ "$candidates" != "$expected" ]; then
  echo "Xcode candidates were not ordered as stable default, newest stable fallbacks, then prereleases." >&2
  diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$candidates") || true
  exit 1
fi

override="$fixture/Xcode_26.0.1.app"
if [ "$(PINES_XCODE_PATH="$override" xcode_candidates)" != "$override" ]; then
  echo "PINES_XCODE_PATH did not take precedence over automatic selection." >&2
  exit 1
fi

if PINES_XCODE_PATH="$fixture/missing.app" xcode_candidates >/dev/null 2>&1; then
  echo "A missing PINES_XCODE_PATH must fail instead of silently falling back." >&2
  exit 1
fi

echo "Xcode candidate selection regression test passed."
