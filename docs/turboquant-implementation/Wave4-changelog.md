# Wave 4 Changelog

Read this alongside:

- `14-worker-launch-schedule.md`
- `15-pr-merge-plan.md`
- `08-worker-ownership.md`
- `10-context-memory-planner.md`
- `11-kv-snapshot-security.md`
- `12-validation-and-release-gates.md`

This file tracks Wave 4 context and persistence implementation after the completed Wave 3 evidence-loop handoff.

Current closeout note: a later production pin pass resolved the local Xcode
package/app validation blocker and marked `compatibility-pair.json` green for
local release gates. Snapshot restore and `Verified`/`Certified` product claims
remain evidence-gated; no real-device tuple was fabricated.

## 2026-05-25

### Start State

- Pines Wave 4 branch: `tq/wave4-context-persistence`.
- Pines branch base: `e94d180` from `tq/wave3-evidence-loop`.
- `mlx-swift-lm` Wave 4 branch: `tq/lm-kv-snapshots`.
- `mlx-swift-lm` branch base: `c934e47` from `tq/lm-profile-v2-quality`.
- `mlx-swift` remains at Wave 3 branch `tq/core-benchmark-json` commit `6a5d5d8`; no active Wave 4 core implementation is scheduled.
- `compatibility-pair.json` remained `pending` at Wave 4 start; Wave 4
  implementation had to stay evidence-gated and could not promote
  Verified/Certified product claims.
- At Wave 4 start, full Xcode package/app validation was blocked by the known local `xcodebuild -resolvePackageDependencies` stall. A later production closeout resolved this local gate.
- Pines worktree had pre-existing generated scheme drift in `Pines.xcodeproj/xcshareddata/xcschemes/Pines.xcscheme` and `PinesWatch.xcscheme` before Wave 4 edits started.

### Wave 4 Scope

- W11: full `ContextAssemblyPlan.v1` planner and segment model.
- W14A: LM compressed KV snapshot export/import with fail-closed validation.
- W14B: Pines encrypted local snapshot manifest/blob/reference store.
- W17: snapshot security policy, atomic writes, quarantine, quota/eviction, deletion hooks, and local-only defaults.
- iOS lifecycle policy: memory warning, thermal, suspend/resume, cancellation and unload policy integration.

### Constraints

- No production pin promotion in Wave 4.
- No `Verified` or `Certified` product claim while `compatibility-pair.json` is pending.
- Snapshot restore may be implemented behind gates, but product activation waits for evidence and validation gates.
- Keep `mlx-swift` W13 Layout V5 work out of Wave 4.
- Do not edit `project.yml`, `Package.resolved`, or generated project files except for pre-existing scheme drift or explicit validation fallout.
- Keep PinesCore MLX-free; snapshot payloads and manifests use local DTOs and serialized blobs.

### Progress

- Created this Wave 4 progress log before implementation edits.
- Created Pines branch `tq/wave4-context-persistence`.
- Created `mlx-swift-lm` branch `tq/lm-kv-snapshots`.
- Launched parallel implementation workers for:
  - W14A LM compressed KV snapshot export/import;
  - W11 Pines context planner;
  - W14B/W17 Pines snapshot store and security.
- Confirmed there is no active `mlx-swift` Wave 4 implementation; W13 Layout V5 remains Wave 5.

### Implementation Completed

- W11 context planner:
  - added full `ContextAssemblyPlan.v1` segment buckets for pinned, live recent, retrieved, summarized,
    compressed KV page, and dropped context;
  - added provenance, citation provenance, privacy boundary, route, retrieval budget, and exact-prefix
    KV validation fields;
  - added deterministic `ContextMemoryPlanner` behavior that keeps pinned system/user-preference context,
    excludes local vault content from cloud plans without explicit approval, keeps semantic memory and
    KV pages distinct, and records summary/retrieval clipping decisions;
  - kept backward decoding for earlier minimal Wave 2 context-plan JSON.
- W14A LM snapshot export/import:
  - added local `KVSnapshotManifest.v1` mirror DTOs and compressed snapshot payload support in
    `mlx-swift-lm`;
  - added export/import for `TurboQuantKVCache` and `RotatingTurboQuantKVCache` without requiring raw KV;
  - import validates schema, identity, layout version, cache kind, preset/backend, group/value bits, seed,
    mode, array names, shapes, dtypes, byte counts, capacity, logical length, ring offset, pinned prefix,
    and resident budget before mutating cache state;
  - fixed the inherited quantized-cache empty-state clear path so snapshot import can discard packed
    fallback state without tripping the base cache fatal path;
  - nested the snapshot tests under the serialized MLX runtime test parent to avoid racing shared MLX cache
    serialization tests during full-package Swift Testing runs.
- W14B/W17 Pines snapshot store/security:
  - added `TurboQuantKVSnapshotManifest.v1`, identity validation, restore gate, write request/outcome,
    restore attempts, quarantine records, blob checksums, and local snapshot store protocol/types;
  - added `SnapshotSecurityPolicy.v1` with local-only, backup-excluded, Keychain-backed, atomic-write,
    quota, eviction, deletion, and fail-closed schema checks;
  - added GRDB schema version 21 with `kv_snapshot_manifest`, `kv_snapshot_blob`,
    `kv_snapshot_reference`, `kv_snapshot_restore_attempt`, and `kv_snapshot_quarantine`;
  - added GRDB commit/list/latest/restore-attempt/quarantine/model-delete/full-delete APIs and mappers;
  - wired model deletion to remove associated KV snapshot rows before deleting the install;
  - restore remains disabled by default through `TurboQuantKVSnapshotRestoreGate.pendingCompatibilityPair`.
- iOS lifecycle policy:
  - confirmed the existing runtime bridge still handles memory warning and critical thermal pressure by
    evicting prompt KV caches, cancelling active generation when required, unloading local runtime, and
    applying constrained local-generation safety policy;
  - Wave 4 snapshot restore remains gated and does not product-activate from lifecycle events.
- Documentation:
  - updated the LM snapshot/speculative doc with the implemented W14A export/import contract;
  - kept `compatibility-pair.json` pending with no Verified/Certified product claim or pin promotion.

### Validation Completed

- Pines:
  - `swift build --disable-automatic-resolution` passed;
  - `swift test --disable-automatic-resolution` passed 175 tests;
  - `swift test --disable-automatic-resolution --filter TurboQuantWave4ContextMemoryTests` passed 7 tests;
  - `swift test --disable-automatic-resolution --filter SnapshotSecurityPolicyTests` passed 6 tests;
  - `swift test --disable-automatic-resolution --filter TurboQuantKVSnapshotStoreTests` passed 6 tests;
  - `swift run --disable-automatic-resolution PinesCoreTestRunner` passed;
  - `bash scripts/ci/check-mlx-package-pins.sh` passed;
  - `compatibility-pair.json` and `compatibility-pair.schema.json` parsed as JSON;
  - `git diff --check` passed;
  - `bash scripts/ci/xcodegen.sh generate` passed;
  - `bash scripts/ci/run-xcode-validation.sh prepare/generate/finalize` passed.
- `mlx-swift-lm`:
  - `swift build --target MLXLMCommon` passed;
  - `swift test --filter TurboQuantKVSnapshotTests` passed 6 tests;
  - `swift test --filter TurboQuantCacheRuntimeSnapshotTests` passed 4 tests;
  - `swift test --filter KVCacheTests` passed 39 tests;
  - `swift test` passed the full package: XCTest phase 115 tests and Swift Testing phase 181 tests;
  - `git diff --check` passed.
- `mlx-swift`:
  - no Wave 4 code changes; branch remains clean on `tq/core-benchmark-json`.

### Wave 4 Handoff Non-Green Gate

- Full Xcode package/app validation was blocked at Wave 4 handoff by the local
  `xcodebuild -resolvePackageDependencies` phase. A Wave 4 resolve attempt
  printed the Xcode invocation and then stalled without further progress; it was
  terminated, and no `xcodebuild` or `XCBBuildService` processes remained
  afterward. The later production closeout resolved this local gate and passed
  `bash scripts/ci/run-xcode-validation.sh all` on the final pair.
- App build/test phases were not run at Wave 4 handoff because they depended on
  that blocked Xcode package-resolution phase.
- The initial generated scheme drift was normalized by pinned XcodeGen generation and is retained as
  generated scheme updates in the Wave 4 commit because `run-xcode-validation.sh generate` requires
  the generated output.

### Handoff Audit

- Re-ran deterministic handoff validation before committing Wave 4.
- Pines validation passed:
  - `git diff --check`;
  - `swift build --disable-automatic-resolution`;
  - `swift test --disable-automatic-resolution` passed 175 Swift Testing tests;
  - `swift test --disable-automatic-resolution --filter TurboQuantWave4ContextMemoryTests` passed 7 tests;
  - `swift test --disable-automatic-resolution --filter SnapshotSecurityPolicyTests` passed 6 tests;
  - `swift test --disable-automatic-resolution --filter TurboQuantKVSnapshotStoreTests` passed 6 tests;
  - `swift run --disable-automatic-resolution PinesCoreTestRunner`;
  - `xcrun swiftc -parse` for changed app/runtime persistence files;
  - `bash scripts/ci/check-mlx-package-pins.sh`;
  - `compatibility-pair.json` JSON parse;
  - `bash scripts/ci/xcodegen.sh generate`;
  - `bash scripts/ci/run-xcode-validation.sh prepare/generate/finalize`.
- `mlx-swift-lm` validation passed:
  - `git diff --check`;
  - `swift build --target MLXLMCommon`;
  - `swift test --filter TurboQuantKVSnapshotTests`;
  - `swift test --filter TurboQuantCacheRuntimeSnapshotTests`;
  - `swift test --filter KVCacheTests`;
  - `swift test`.
- Confirmed `mlx-swift` has no Wave 4 diff and remains clean on `tq/core-benchmark-json`.
- Confirmed no `xcodebuild` or `XCBBuildService` processes remained after validation.
