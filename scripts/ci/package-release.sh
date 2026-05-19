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

This is a source/developer-preview release for the local-first iOS app foundation. It is not a signed App Store or TestFlight build.

License: PolyForm Noncommercial License 1.0.0. Commercial use requires a separate written license from Schtack.
Third-party dependency notices are documented in THIRD_PARTY_NOTICES.md.
The GitHub Release includes a CycloneDX SBOM generated from the committed SwiftPM and npm lockfiles.

Build locally with:

\`\`\`sh
bash scripts/ci/xcodegen.sh generate
swift build --disable-automatic-resolution
swift test --disable-automatic-resolution
swift run --disable-automatic-resolution PinesCoreTestRunner
npm --prefix site ci
npm --prefix site run build
bash scripts/ci/run-xcode-validation.sh
\`\`\`

Full iOS validation requires full Xcode 26 with the iOS and watchOS platform payloads available to \`xcodebuild\`, an available iPhone simulator for CI smoke tests, and the committed Xcode app package lockfile. Real-device TurboQuant acceptance and App Store privacy review remain separate release gates before a production distribution.
NOTES

(
  cd "$dist"
  tar -czf "pines-${tag}-source.tar.gz" "pines-${tag}"
  shasum -a 256 "pines-${tag}-source.tar.gz" > "pines-${tag}-source.tar.gz.sha256"
)

bash "$root/scripts/ci/generate-release-sbom.sh" "$tag" "$dist/pines-${tag}-sbom.cdx.json"

echo "$dist/pines-${tag}-source.tar.gz"
