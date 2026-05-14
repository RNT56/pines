# Security And Privacy

`pines` is designed as a local-first app. The default product boundary is that chats, model state, vault documents, embeddings, and normal inference remain on device.

## Secrets

- API keys must be stored in Keychain through `SecretStore`.
- Keys must not be stored in SQLite, UserDefaults, CloudKit, logs, or audit payloads.
- Public examples must not include real or realistic secret literals.
- `Redactor` is used to strip common API-key shapes from diagnostic payloads.

## Cloud Execution

Cloud execution is BYOK-only and opt-in through agent policy. The router must not silently fall back from local inference to cloud.

Allowed execution modes:

- `localOnly`
- `preferLocal`
- `cloudAllowed`
- `cloudRequired`

If cloud is required but not configured, execution must fail with a consent/configuration path.

## Tool Execution

Tools are deny-by-default. Tool specs include:

- JSON schemas
- permissions
- side-effect level
- network policy
- timeout
- explanation requirement

Web and browser outputs should be treated as untrusted content. Browser automation must require visible user approval for login, checkout, posting, upload, credential-adjacent, or remote-state-changing actions.

## Sync Boundary

Optional iCloud sync may sync conversations, tags, vault metadata, settings, and source documents after user opt-in.

Do not sync:

- API keys
- model binaries
- prompt caches
- generated embeddings by default
- transient tool/browser state
