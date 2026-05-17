#!/usr/bin/env bash
set -euo pipefail

manifest="${1:-Pines/PrivacyInfo.xcprivacy}"

echo "Checking privacy manifest..."
test -f "$manifest"
plutil -lint "$manifest" >/dev/null

tracking="$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyTracking' "$manifest")"
if [ "$tracking" != "false" ]; then
  echo "NSPrivacyTracking must remain false for the local-first default release." >&2
  exit 1
fi

if ! /usr/libexec/PlistBuddy -c 'Print :NSPrivacyCollectedDataTypes' "$manifest" >/dev/null; then
  echo "Privacy manifest must declare NSPrivacyCollectedDataTypes." >&2
  exit 1
fi

if ! /usr/libexec/PlistBuddy -c 'Print :NSPrivacyAccessedAPITypes' "$manifest" >/dev/null; then
  echo "Privacy manifest must declare required-reason API access." >&2
  exit 1
fi

if ! grep -q 'NSPrivacyAccessedAPICategoryFileTimestamp' "$manifest"; then
  echo "Privacy manifest must include file timestamp required-reason API usage." >&2
  exit 1
fi

if ! grep -q 'NSPrivacyAccessedAPICategoryDiskSpace' "$manifest"; then
  echo "Privacy manifest must include disk space required-reason API usage." >&2
  exit 1
fi

echo "Privacy manifest checks passed."
