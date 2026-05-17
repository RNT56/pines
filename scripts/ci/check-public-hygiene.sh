#!/usr/bin/env bash
set -euo pipefail

echo "Checking git diff whitespace..."
git diff --check

echo "Checking repository license files..."
test -f LICENSE
test -f NOTICE
grep -q "PolyForm Noncommercial License 1.0.0" LICENSE
grep -q "Required Notice:" NOTICE
grep -q "PolyForm-Noncommercial-1.0.0" README.md
grep -q "PolyForm-Noncommercial-1.0.0" CONTRIBUTING.md
bash scripts/ci/check-third-party-notices.sh
bash scripts/ci/check-mlx-package-pins.sh

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
if git ls-files | grep -E '(^|/)(\.build|DerivedData|xcuserdata)(/|$)'; then
  echo "Generated or local developer artifacts are tracked." >&2
  exit 1
fi

echo "Public repository hygiene checks passed."
