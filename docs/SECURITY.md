# Security And Privacy

`pines` is designed as a local-first app. The default product boundary is that chats, model state, vault documents, embeddings, attachments, and normal inference remain on device unless the user configures a BYOK provider and chooses a cloud route.

## Secrets

- API keys must be stored in Keychain through `SecretStore`.
- Keys must not be stored in SQLite, UserDefaults, CloudKit, logs, or audit payloads.
- Public examples must not include real or realistic secret literals.
- `Redactor` is used to strip common API-key shapes from diagnostic payloads.

## Cloud Execution

Cloud execution is BYOK-only. Normal chat can use a selected or configured BYOK provider according to the user's execution mode and provider selection, but the router must not silently fall back from local inference to cloud.

Allowed execution modes:

- `localOnly`
- `preferLocal`
- `cloudAllowed`
- `cloudRequired`

If cloud is required but not configured, execution must fail with a consent/configuration path. Local vault and MCP resource context is not sent to cloud automatically; the app presents a per-turn approval sheet so the user can send without that context or explicitly include it.

## Tool Execution

Tools are deny-by-default. Tool specs include:

- JSON schemas
- permissions
- side-effect level
- network policy
- timeout
- explanation requirement

Web and browser outputs should be treated as untrusted content. Browser automation must require visible user approval for login, checkout, posting, upload, credential-adjacent, or remote-state-changing actions. Normal chat does not advertise all registered tools by default; tool-enabled agent flows and MCP sampling keep their own policy checks.

## Sync Boundary

Optional iCloud sync may sync settings, conversations, messages, vault metadata, vault chunks, and source documents after user opt-in.

CloudKit repository merge/apply code lives in `GRDBPinesStore+CloudKit.swift` so the sync boundary stays isolated from the base local-store implementation.

Do not sync:

- API keys
- model binaries
- prompt caches
- generated embeddings and compressed vector codes by default
- transient tool/browser state

Generated embeddings and compressed vector codes sync only when private iCloud sync and the separate embedding sync toggle are both enabled. Chat attachments remain local files; when a user chooses cloud execution, supported image/PDF/text attachments can be encoded into the provider request for that turn according to provider capability checks.

Chat attachment imports use user-selected files, stage local copies under app support storage, and reject empty or oversized files before request construction. HEIC/HEIF inputs are converted to JPEG at import time, so the original local file is not sent directly to providers. Message row actions can copy content, edit user-authored text while no run is active, or import local message attachments into Vault; Vault import follows the normal local ingestion and embedding-approval flow.

MCP bearer tokens and OAuth access/refresh tokens follow the same Keychain-only rule as BYOK provider keys.
