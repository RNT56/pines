# Security And Privacy

`pines` is designed as a local-first app. The default product boundary is that chats, model state, vault documents, embeddings, attachments, and normal inference remain on device unless the user configures a BYOK provider and chooses a cloud route.

## Secrets

- API keys must be stored in Keychain through `SecretStore` or the typed `SecureKeyStore` wrapper.
- Device-local secrets use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- The CloudKit E2E content key is the only synchronizable secret. It uses a stable key ID, iCloud Keychain synchronization, and `kSecAttrAccessibleWhenUnlocked`.
- Keys must not be stored in SQLite, UserDefaults, CloudKit, logs, or audit payloads.
- Cloud provider custom headers use typed `CloudProviderHeader` values. Secret-like names such as `Authorization`, `Cookie`, names containing `key`, `token`, `secret`, `credential`, or `password` must be stored as Keychain references, not plaintext header values.
- Public examples must not include real or realistic secret literals.
- `Redactor` strips OpenAI/Anthropic/Gemini/Voyage/Hugging Face/Brave/GitHub-style keys, bearer tokens, OAuth/JWT/cookie values, private keys, and generic long credential shapes from diagnostics and audit records.

## Local Storage

The production local store is SQLCipher-backed GRDB. `GRDBPinesStore` derives a 256-bit database key from `SecureKeyStore`, applies the key before normal repository access, verifies `PRAGMA cipher_version`, and fails closed if SQLCipher is unavailable.

On first secure launch, an existing plaintext `pines.sqlite` is copied into a keyed database, critical row counts are verified, the encrypted file replaces the plaintext file, and plaintext SQLite/WAL/SHM files are deleted on a best-effort basis. Flash storage cannot guarantee forensic wipe, so release notes must describe the migration as best-effort deletion rather than cryptographic erasure.

Vault source payloads are written through `EncryptedBlobStore` with CryptoKit `AES.GCM`, random nonces, SHA-256 verification, complete file protection, and backup exclusion. Chat attachment staging uses complete file protection and backup exclusion; provider requests still perform per-turn capability and size checks before reading staged files.

## Cloud Execution

Cloud execution is BYOK-only. Normal chat can use a selected or configured BYOK provider according to the user's execution mode and provider selection, but the router must not silently fall back from local inference to cloud.

Allowed execution modes:

- `localOnly`
- `preferLocal`
- `cloudAllowed`
- `cloudRequired`

If cloud is required but not configured, execution must fail with a consent/configuration path. Local vault and MCP resource context is not sent to cloud automatically; the app presents a per-turn approval sheet so the user can send without that context or explicitly include it.

All remote endpoints must use HTTPS. `EndpointSecurityPolicy` is shared by BYOK providers, MCP endpoints, OAuth authorization/token URLs, model catalog calls, and `web.fetch`. `http://localhost`, `http://127.0.0.1`, and `http://[::1]` are allowed only when the integration has an explicit local-development flag. RFC1918/LAN HTTP is never treated as local.

Provider-hosted resources are explicit cloud resources. OpenAI files/vector stores, Anthropic files, Gemini files/context caches, provider batches, generated media, generated files, realtime/live sessions, and Deep Research runs are shown through provider lifecycle records and must stay visually distinct from local Vault documents. Uploading a Vault document to a provider, importing a provider artifact into Vault, deleting a local Vault file, and deleting a provider-hosted copy are separate user-visible actions.

Provider tools run outside the device unless clearly labeled otherwise. Anthropic/OpenAI/Gemini hosted search, fetch, code execution, remote MCP, text editor/bash, computer use, generated media, token counting, and batch requests may send prompts, attachments, provider file references, or derived context to the provider. Normal chat may use low-risk provider search/fetch only through explicit enablement; code execution, remote MCP, text editor/bash, and computer use require stronger approval and environment labels. Computer use remains disabled until a dedicated safety UX exists.

## Tool Execution

Tools are deny-by-default. Tool specs include:

- JSON schemas
- permissions
- side-effect level
- network policy
- timeout
- explanation requirement

Web and browser outputs should be treated as untrusted content. Browser automation must require visible user approval for login, checkout, posting, upload, credential-adjacent, or remote-state-changing actions. Local private-data tools for vault, attachment, and conversation reads are scoped through repository and run context rather than arbitrary filesystem paths, and they carry the cloud-context permission so BYOK runs require explicit private-context approval. Normal chat does not advertise all registered tools by default; tool-enabled agent flows and MCP sampling keep their own policy checks.

## Sync Boundary

Optional iCloud sync may sync settings, conversations, messages, vault metadata, and vault chunks after user opt-in.

CloudKit repository merge/apply code lives in `GRDBPinesStore+CloudKit.swift` so the sync boundary stays isolated from the base local-store implementation.

CloudKit uses the encrypted private zone `PinesPrivateEncryptedV1`. `CloudKitRecordCipher` encrypts record payloads with `AES.GCM` before upload; only record type, record name, updated timestamp, tombstone flag, schema version, nonce, key ID, ciphertext, and tag are visible to CloudKit. After encrypted sync succeeds, the service attempts to delete the legacy plaintext `PinesPrivate` zone.

Do not sync:

- API keys
- model binaries
- prompt caches
- provider-hosted file contents, provider context caches, provider batch payloads, realtime/live session payloads, or generated provider artifacts unless a later explicit sync/export workflow encrypts them first
- generated embeddings and compressed vector codes by default
- TurboQuant KV snapshots by default
- transient tool/browser state

Generated embeddings and compressed vector codes sync only when private iCloud sync and the separate embedding sync toggle are both enabled. Chat attachments remain local files; when a user chooses cloud execution, supported image/PDF/text attachments can be encoded into the provider request for that turn according to provider capability checks.

TurboQuant KV snapshots are local encrypted blobs. They are bound to model, tokenizer, profile, RoPE, prefix, layout, and compatibility-pair identity, and restore fails closed on mismatch or corruption. Snapshot deletion is included in model deletion and data-erasure flows.

Chat attachment imports use user-selected files, stage local copies under app support storage, and reject empty or oversized files before request construction. HEIC/HEIF inputs are converted to JPEG at import time, so the original local file is not sent directly to providers. Message row actions can copy content, edit user-authored text while no run is active, or import local message attachments into Vault; Vault import follows the normal local ingestion and embedding-approval flow.

MCP bearer tokens and OAuth access/refresh tokens follow the same Keychain-only rule as BYOK provider keys.

## Security Reset

The one-time `SecurityResetCoordinator` preserves chats, vault data, settings, models, and audit history, then deletes existing provider keys, MCP bearer/OAuth tokens, Brave Search keys, Hugging Face tokens, and legacy custom headers. Provider and MCP display names and URLs are kept only when they pass `EndpointSecurityPolicy`; otherwise the integration is disabled and a redacted audit event is recorded. Users must re-enter credentials after the reset.

## Release Gates

Every production release must pass:

- `swift test --disable-automatic-resolution`
- `scripts/ci/check-public-hygiene.sh`
- `scripts/ci/check-mlx-package-pins.sh`
- `scripts/ci/run-xcode-validation.sh all`
- encrypted-store migration verification against a plaintext fixture
- CloudKit encrypted-zone verification showing no plaintext payload fields in `PinesPrivateEncryptedV1`
- App Store privacy manifest review for the signed archive

TurboQuant model/device/mode compatibility claims require separate real-device evidence. A green runtime compatibility pair is necessary for local release, but it is not sufficient to label a model profile `Verified` or `Certified`.
