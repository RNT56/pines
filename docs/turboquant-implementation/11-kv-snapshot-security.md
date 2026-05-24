# KV Snapshot Security

KV snapshots are a powerful UX unlock and a correctness risk. They must be local, encrypted, identity-validated, quota-limited, and fail closed.

Launch wave: Snapshot export/import and storage are Wave 4. Snapshot design can be reviewed earlier, but product activation waits for lifecycle, evidence, and security gates.

## Product goal

Enable:

```text
close app -> reopen session -> continue without full prefill
```

without cloud dependency and without accepting stale model state.

## Snapshot identity

A compressed KV snapshot is valid only when all identity fields match:

- model ID;
- model revision;
- tokenizer hash;
- profile hash;
- TurboQuant layout version;
- RoPE config hash;
- token prefix hash;
- logical length;
- pinned prefix length;
- fallback/precision policy where relevant.

Any mismatch invalidates restore.

## KVSnapshotManifest.v1

```swift
public struct TurboQuantKVSnapshotManifest: Codable, Sendable {
    public var schemaVersion: Int
    public var snapshotID: UUID
    public var conversationID: UUID
    public var modelID: String
    public var modelRevision: String?
    public var tokenizerHash: String
    public var profileHash: String
    public var turboQuantLayoutVersion: Int
    public var ropeConfigHash: String
    public var tokenPrefixHash: String
    public var fallbackContractHash: String?
    public var logicalLength: Int
    public var pinnedPrefixLength: Int
    public var compressedKeyBytes: Int64
    public var compressedValueBytes: Int64
    public var blobByteCount: Int64
    public var encryptionKeyID: String
    public var createdAt: Date
}
```

## SnapshotSecurityPolicy.v1

```swift
public struct SnapshotSecurityPolicy: Codable, Sendable {
    public var schemaVersion: Int
    public var encryptedAtRest: Bool
    public var keySource: String
    public var cloudSyncAllowed: Bool
    public var atomicWriteRequired: Bool
    public var partialWriteQuarantine: Bool
    public var quotaBytes: Int64
    public var evictionPolicy: String
    public var deleteOnModelDeletion: Bool
    public var deleteOnDataErasure: Bool
}
```

Defaults:

- encrypted at rest: yes;
- key source: Keychain-backed local key;
- CloudKit sync: no;
- atomic write: required;
- partial write quarantine: required;
- quota: device-class dependent;
- delete on model deletion: yes unless user explicitly preserves incompatible metadata;
- delete on data erasure: yes.

## Storage design

Tables:

- `kv_snapshot_manifest`;
- `kv_snapshot_blob`;
- `kv_snapshot_reference`;
- `kv_snapshot_restore_attempt`;
- `kv_snapshot_quarantine`.

Blob requirements:

- encrypted local blob;
- no iCloud backup/sync unless explicitly designed and approved later;
- atomic temp-write then rename/commit;
- integrity check;
- corruption quarantine;
- quota enforcement.

## Restore flow

1. Find latest snapshot for conversation/session.
2. Decode manifest envelope.
3. Verify schema compatibility.
4. Verify model/tokenizer/profile/RoPE/prefix/fallback identity.
5. Verify blob existence and integrity.
6. Decrypt blob.
7. Ask LM to import compressed cache pages.
8. Validate cache layout before use.
9. Run next-token equivalence test in benchmark mode, not every product restore.
10. Record restore attempt.

## Failure behavior

| Failure | Behavior |
| --- | --- |
| schema missing/newer incompatible | reject snapshot |
| model mismatch | reject snapshot |
| tokenizer mismatch | reject snapshot |
| profile mismatch | reject snapshot |
| RoPE mismatch | reject snapshot |
| prefix mismatch | reject snapshot and re-prefill |
| missing blob | mark stale and re-prefill |
| partial write | quarantine |
| corruption | quarantine |
| decryption failure | quarantine and typed failure |
| import validation failure | reject before cache use |

## LM export/import contract

LM must provide:

- export compressed arrays/pages;
- import compressed arrays/pages;
- validate layout before import;
- include logical length;
- include ring offset;
- include pinned prefix;
- expose runtime snapshot after import;
- fail before use on invalid manifest.

Acceptance:

- export/import roundtrip produces same next-token logits within tolerance;
- invalid manifest fails before cache use;
- raw KV is not required for restore.

## Privacy requirements

- Snapshots are local-only by default.
- Snapshots do not sync through CloudKit.
- Support export redacts or excludes snapshot blobs by default.
- User data deletion removes snapshots.
- Model deletion removes associated snapshots.
- Snapshot metadata is treated as model-derived private state.

## Quota and eviction

Quota policy should consider:

- device class;
- available disk;
- model size;
- active conversation count;
- snapshot age;
- recent use;
- user pinning.

Eviction order:

1. quarantined snapshots;
2. invalidated snapshots;
3. old unpinned snapshots;
4. least recently used snapshots;
5. largest snapshots.

## Tests

Required:

- valid restore after app restart;
- prefix mismatch rejects restore;
- model revision mismatch rejects restore;
- tokenizer mismatch rejects restore;
- partial write quarantines;
- corruption quarantines;
- data erasure deletes snapshots;
- model deletion deletes snapshots;
- CloudKit exclusion is enforced;
- quota eviction works.
