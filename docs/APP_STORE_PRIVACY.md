# App Store Privacy Review Notes

`pines` remains local-first by default. The production implementation uses on-device SQLite, Keychain, local model binaries, local chat/vault attachments, optional CloudKit private database sync, optional BYOK cloud inference, optional MCP servers, and optional Brave Search.

## Privacy Nutrition Label Defaults

- Data collection: none for tracking.
- Tracking: disabled.
- Tracking domains: none.
- Optional CloudKit sync stores user content only in the user's private iCloud database after opt-in.
- Optional BYOK providers send prompts only when the user selects or enables cloud execution for the current chat, agent, or MCP sampling flow.
- Local vault and selected MCP resource context is sent to a BYOK provider only after per-turn approval.
- Chat attachments are stored as local files. HEIC/HEIF selections are converted to JPEG during local staging. If cloud execution is selected, supported image, PDF, or text attachments can be encoded into the provider request for that turn.
- Message row actions can copy message text or attachment names to the pasteboard, edit user-authored message text, and import local message attachments into Vault; Vault imports remain local unless the user separately enables cloud embedding or sync features.
- API keys are stored only in Keychain and are not written to SQLite, CloudKit, logs, or audit payloads.

## Required-Reason API Review

Current manifest entries:

- `NSPrivacyAccessedAPICategoryFileTimestamp` with reason `C617.1` for local file import, chat attachments, model download resume, SQLite/GRDB file management, and vault source metadata.
- `NSPrivacyAccessedAPICategoryDiskSpace` with reason `E174.1` for model install preflight, resumable downloads, and user-visible storage/runtime readiness.

`Info.plist` also contains photo-library and camera usage descriptions for selected or captured image prompts/imports. Current chat and vault imports use user-selected files; final submission should keep these strings only if the direct photo/camera entry points remain in scope.

Final App Store submission must re-run this review after Xcode resolves the complete package graph for GRDB, the pinned MLX forks, Swift Hugging Face, Swift Transformers, PDFKit, Vision, WebKit, and CloudKit.

CI runs `scripts/ci/check-privacy-manifest.sh` to lint the committed manifest shape, tracking flag, and required-reason API declarations. This is a repository guardrail only; it does not replace App Store Connect's final privacy review for a signed production build.
