#!/usr/bin/env bash
set -euo pipefail

check_whitespace() {
  echo "Checking git diff whitespace..."

  if [ "${CI:-}" = "true" ]; then
    if [ "${GITHUB_EVENT_NAME:-}" = "pull_request" ] && [ -n "${GITHUB_BASE_REF:-}" ]; then
      local base_ref="origin/${GITHUB_BASE_REF}"
      if ! git rev-parse --verify --quiet "${base_ref}^{commit}" >/dev/null; then
        git fetch --no-tags --depth=1 origin "${GITHUB_BASE_REF}:refs/remotes/${base_ref}" || true
      fi
      if git rev-parse --verify --quiet "${base_ref}^{commit}" >/dev/null; then
        git diff --check "${base_ref}...HEAD"
        return
      fi
    fi

    if [ -n "${GITHUB_EVENT_BEFORE:-}" ] &&
      [[ ! "${GITHUB_EVENT_BEFORE}" =~ ^0+$ ]] &&
      git rev-parse --verify --quiet "${GITHUB_EVENT_BEFORE}^{commit}" >/dev/null; then
      git diff --check "${GITHUB_EVENT_BEFORE}..HEAD"
      return
    fi
  fi

  git diff --check HEAD --
}

check_whitespace

echo "Checking repository license files..."
test -f LICENSE
test -f NOTICE
grep -q "PolyForm Noncommercial License 1.0.0" LICENSE
grep -q "Required Notice:" NOTICE
grep -q "PolyForm-Noncommercial-1.0.0" README.md
grep -q "PolyForm-Noncommercial-1.0.0" CONTRIBUTING.md
bash scripts/ci/check-third-party-notices.sh
bash scripts/ci/check-mlx-package-pins.sh
bash scripts/ci/check-privacy-manifest.sh
bash scripts/ci/check-security-boundaries.sh
bash scripts/ci/check-action-pins.sh

echo "Checking tracked files for common secret patterns..."
github_oauth="gh""o_"
github_pat="gh""p_"
openai_prefix="sk-"
huggingface_prefix="hf_"
google_prefix="AIza"
private_key_marker='BEGIN (RSA|OPENSSH|PRIVATE)'
secret_pattern="${github_oauth}|${github_pat}|${openai_prefix}[A-Za-z0-9_-]{12,}|${huggingface_prefix}[A-Za-z0-9_-]{12,}|${google_prefix}[A-Za-z0-9_-]{12,}|${private_key_marker}"

if git grep -n -I -E "$secret_pattern" -- . ':!scripts/ci/check-public-hygiene.sh'; then
  echo "Potential secret-like value found in tracked files." >&2
  exit 1
fi

echo "Checking generated/build artifacts are not tracked..."
if git ls-files | grep -E '(^|/)(\.build|DerivedData|xcuserdata|node_modules|\.astro|\.netlify|build|dist)(/|$)'; then
  echo "Generated or local developer artifacts are tracked." >&2
  exit 1
fi

echo "Public repository hygiene checks passed."
