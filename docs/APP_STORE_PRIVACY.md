# App Store Privacy Review Notes

`pines` remains local-first by default. The production implementation uses on-device SQLite, Keychain, local model binaries, optional CloudKit private database sync, optional BYOK cloud inference, and optional Brave Search.

## Privacy Nutrition Label Defaults

- Data collection: none for tracking.
- Tracking: disabled.
- Tracking domains: none.
- Optional CloudKit sync stores user content only in the user's private iCloud database after opt-in.
- Optional BYOK providers send prompts only when the user explicitly enables cloud execution for an agent/session.
- API keys are stored only in Keychain and are not written to SQLite, CloudKit, logs, or audit payloads.

## Required-Reason API Review

Current manifest entries:

- `NSPrivacyAccessedAPICategoryFileTimestamp` with reason `C617.1` for local file import, model download resume, SQLite/GRDB file management, and vault source metadata.
- `NSPrivacyAccessedAPICategoryDiskSpace` with reason `E174.1` for model install preflight, resumable downloads, and user-visible storage/runtime readiness.

Final App Store submission must re-run this review after Xcode resolves the complete package graph for GRDB, the pinned MLX forks, Swift Hugging Face, Swift Transformers, PDFKit, Vision, WebKit, and CloudKit.
