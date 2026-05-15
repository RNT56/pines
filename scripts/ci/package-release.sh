#!/usr/bin/env bash
set -euo pipefail

tag="${1:?usage: package-release.sh <tag>}"
root="$(git rev-parse --show-toplevel)"
dist="$root/dist"
bundle="$dist/pines-${tag}"

rm -rf "$dist"
mkdir -p "$bundle"

git archive --format=tar HEAD | tar -x -C "$bundle"

for required_file in LICENSE NOTICE THIRD_PARTY_NOTICES.md; do
  test -f "$bundle/$required_file"
done

cat > "$bundle/RELEASE_NOTES.md" <<NOTES
# pines ${tag}

This is a source/developer-preview release for the local-first iOS app foundation.

License: PolyForm Noncommercial License 1.0.0. Commercial use requires a separate written license from Schtack.
Third-party dependency notices are documented in THIRD_PARTY_NOTICES.md.

Build locally with:

\`\`\`sh
xcodegen generate
swift build
swift run PinesCoreTestRunner
\`\`\`

Full iOS validation requires full Xcode 26 selected via \`xcode-select\`.
NOTES

(
  cd "$dist"
  tar -czf "pines-${tag}-source.tar.gz" "pines-${tag}"
  shasum -a 256 "pines-${tag}-source.tar.gz" > "pines-${tag}-source.tar.gz.sha256"
)

echo "$dist/pines-${tag}-source.tar.gz"
