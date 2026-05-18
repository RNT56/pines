#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project_file="$root/project.yml"

project_version="$(
  awk -F'"' '/minimumXcodeGenVersion:/ { print $2; exit }' "$project_file"
)"
version="${PINES_XCODEGEN_VERSION:-$project_version}"

case "$version" in
  2.45.4)
    archive_sha="${PINES_XCODEGEN_SHA256:-090ec29491aad50aec10631bf6e62253fed733c50f3aab0f5ffc86bc170bdbef}"
    ;;
  *)
    if [ -z "${PINES_XCODEGEN_SHA256:-}" ]; then
      echo "No pinned SHA-256 is configured for XcodeGen $version." >&2
      echo "Update scripts/ci/xcodegen.sh when changing project.yml minimumXcodeGenVersion." >&2
      exit 1
    fi
    archive_sha="$PINES_XCODEGEN_SHA256"
    ;;
esac

tool_root="${PINES_XCODEGEN_TOOL_ROOT:-$root/build/tools/xcodegen}"
install_dir="$tool_root/$version"
pinned_bin="$install_dir/xcodegen/bin/xcodegen"
release_url="https://github.com/yonaskolb/XcodeGen/releases/download/$version/xcodegen.zip"

installed_version() {
  "$1" --version 2>/dev/null | awk '/Version:/ { print $2; exit }'
}

if [ -x "$pinned_bin" ] && [ "$(installed_version "$pinned_bin")" = "$version" ]; then
  exec "$pinned_bin" "$@"
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/pines-xcodegen.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

archive="$tmp_dir/xcodegen.zip"
curl -fsSL "$release_url" -o "$archive"

actual_sha="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
if [ "$actual_sha" != "$archive_sha" ]; then
  echo "XcodeGen archive checksum mismatch for $release_url" >&2
  echo "expected: $archive_sha" >&2
  echo "actual:   $actual_sha" >&2
  exit 1
fi

unzip -q "$archive" -d "$tmp_dir/unpacked"
rm -rf "$install_dir"
mkdir -p "$install_dir"
mv "$tmp_dir/unpacked/xcodegen" "$install_dir/xcodegen"
chmod +x "$pinned_bin"

exec "$pinned_bin" "$@"
