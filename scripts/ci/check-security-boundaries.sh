#!/usr/bin/env bash
set -euo pipefail

echo "Checking high-assurance security boundaries..."

if git grep -n -I "extraHeadersJSON" -- . ':!scripts/ci/check-security-boundaries.sh'; then
  echo "Deprecated plaintext cloud provider header API is still referenced." >&2
  exit 1
fi

if git grep -n -I "extra_headers_json" -- . \
  ':!Sources/PinesCore/Persistence/DatabaseSchema.swift' \
  ':!Pines/Persistence/GRDBPinesStore.swift' \
  ':!scripts/ci/check-security-boundaries.sh'; then
  echo "Legacy plaintext custom-header column escaped the schema reset path." >&2
  exit 1
fi

if git grep -n -I "kSecAttrAccessibleAfterFirstUnlock" -- . ':!scripts/ci/check-security-boundaries.sh'; then
  echo "Keychain items must not use AfterFirstUnlock accessibility for secrets." >&2
  exit 1
fi

if git grep -n -I -E 'http://(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)' -- Pines Sources; then
  echo "LAN HTTP must not be treated as local development." >&2
  exit 1
fi

if git grep -n -I -E 'lastValidationError\s*=\s*result\.message|lastError\s*=\s*error\.localizedDescription' -- Pines Sources; then
  echo "Provider and MCP persisted errors must pass through Redactor." >&2
  exit 1
fi

if git grep -n -I 'PinesPrivate"' -- Pines Sources ':!Pines/Cloud/CloudKitSyncService.swift'; then
  echo "Plaintext CloudKit zone references must remain confined to legacy-zone deletion." >&2
  exit 1
fi

echo "Security boundary checks passed."
