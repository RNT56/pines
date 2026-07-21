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

store_path="Pines/Persistence/GRDBPinesStore.swift"
grep -Fq 'throw StoreSecurityError.sqlCipherUnavailable' "$store_path"
grep -Fq 'PRAGMA cipher_version' "$store_path"
grep -Fq 'PRAGMA cipher_memory_security = ON' "$store_path"

if git grep -n -I -E 'access_token|refresh_token|oauth_client_secret|client_secret' -- \
  Sources/PinesCore/Persistence/DatabaseSchema.swift \
  "$store_path"; then
  echo "OAuth secrets must never be persisted in the application database." >&2
  exit 1
fi

grep -Fq 'secretStore.write(token.accessToken' Pines/MCP/MCPOAuthService.swift
grep -Fq 'secretStore.write(refreshToken' Pines/MCP/MCPOAuthService.swift

echo "Security boundary checks passed."
