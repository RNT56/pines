# Wave 7 Changelog

Read this alongside:

- `14-worker-launch-schedule.md`
- `15-pr-merge-plan.md`
- `08-worker-ownership.md`
- `12-validation-and-release-gates.md`
- `13-complete-task-inventory.md`

Wave 7 is the post-Wave-6 W29+/MVP 6 platform-unlock implementation lane. The
central schedule does not define a named Wave 7, so this changelog scopes Wave 7
to the remaining W29+ platform backlog while preserving all Wave 6 release gates.

## 2026-05-25

### Start State

- Pines Wave 7 branch: `tq/wave7-platform-unlocks`.
- Pines branch base: `d35e685` from `tq/pines-speculative`.
- `mlx-swift-lm` Wave 7 branch: `tq/wave7-lm-platform`.
- `mlx-swift-lm` branch base: `bb993db` from `tq/lm-speculative`.
- `mlx-swift` Wave 7 branch: `tq/wave7-core-platform`.
- `mlx-swift` branch base: `741fa31` from `tq/layout-v5-kernels`.
- `compatibility-pair.json` remained `pending` at Wave 7 start; Wave 7 could
  not promote Verified, Certified, Fast, adaptive precision, open-format, mesh,
  memory, or agent product claims without a green compatibility pair and
  evidence.
- Full local Xcode package/app validation was still blocked at Wave 7 start by
  the known `xcodebuild -resolvePackageDependencies` stall. The later
  production closeout resolved this local gate and passed
  `bash scripts/ci/run-xcode-validation.sh all` on the final pair.
- Pines retains the pre-existing generated scheme drift in:
  - `Pines.xcodeproj/xcshareddata/xcschemes/Pines.xcscheme`
  - `Pines.xcodeproj/xcshareddata/xcschemes/PinesWatch.xcscheme`

### Wave 7 Scope

- W29+ platform unlock contracts:
  - adaptive precision;
  - segment precision;
  - layer and head sensitivity metadata;
  - semantic memory and user fact store policy;
  - multimodal memory policy;
  - local agent memory and tool-state pinning policy;
  - open KV format and safetensors/export metadata;
  - device mesh and encrypted LAN sync policy;
  - personalization/adapters policy;
  - release kill-switch hardening.
- All features remain disabled by default, kill-switched, and evidence-required.
- Product activation is out of scope until release gates are explicitly green.

### Constraints

- Do not edit production pins, `project.yml`, `Package.resolved`, or generated
  Xcode project files for Wave 7.
- Do not edit `Pines/Runtime/MLXRuntimeBridge.swift` unless Wave 7 explicitly
  creates a serialized INT owner.
- Keep semantic memory and KV snapshots distinct.
- Keep open KV format local/export metadata fail-closed until identity,
  encryption, and evidence policies are satisfied.
- Do not change speculative DTO compatibility unless all evidence and importer
  dimensions are migrated together.

### Progress

- Created this Wave 7 progress log before implementation edits.
- Created Wave 7 branches for Pines, `mlx-swift-lm`, and `mlx-swift`.
- Launched parallel implementation workers for:
  - Core MLX Wave 7 platform/adaptive/open-format contracts;
  - LM Wave 7 platform/adaptive/open-format contracts.
- Pines owns the central Wave 7 platform gates, admission/evidence shims, schema
  registry, persistence-facing DTOs, and tests.

### Completed Implementation

- Pines:
  - Added fail-closed Wave 7 platform-unlock DTOs for adaptive precision,
    precision segments, sensitivity metadata, semantic/multimodal/agent memory,
    open KV format, device mesh, personalization/adapters, platform evidence,
    and admission budget accounting.
  - Expanded platform feature IDs to cover the W29+/MVP 6 backlog and made the
    runtime default set the Wave 7 disabled-default matrix.
  - Threaded optional platform-unlock budget into local runtime admission memory
    zones without enabling any product behavior by default.
  - Added platform evidence dimensions to run decisions, benchmark runtime
    imports, profile evidence lookup/conflict checks, and GRDB evidence
    persistence.
  - Added database migration 23, schema-registry entries, compatibility-pair
    schema names, and Wave 7 contract tests.
  - Updated central docs, worker ownership, launch/merge plan, inventory, and
    schema-registry documentation for Wave 7.
- `mlx-swift`:
  - Added core-only platform policy contracts for Wave 7 feature gates,
    adaptive precision policy, precision segments, open KV descriptors, and
    evidence-gated activation.
  - Added focused Wave 7 core platform tests and updated core worker docs.
- `mlx-swift-lm`:
  - Added LM-only Wave 7 platform policy contracts for adaptive precision,
    semantic memory, agent memory, open KV, personalization/adapters, and
    evidence-gated activation.
  - Added focused LM Wave 7 platform tests.

### Validation

- Pines:
  - `swift test --filter TurboQuantWave7PlatformTests` passed.
  - `swift test --filter 'TurboQuantWave7PlatformTests|CoreContractTests/turboQuantSchemaRegistryExposesCanonicalWave0Names|CoreContractTests/openAIParityMigrationAddsTablesAndRunProvenance'` passed.
  - `swift test --filter 'TurboQuantWave6SpeculativeTests|TurboQuantWave7PlatformTests'` passed.
  - `swift build` passed.
  - `swift test --disable-automatic-resolution` passed.
  - `swift run --disable-automatic-resolution PinesCoreTestRunner` passed.
  - `git diff --check` passed.
- `mlx-swift-lm`:
  - `swift test --filter TurboQuantWave7PlatformTests` passed.
  - Full `swift test` passed.
  - `swift build --target MLXLMCommon` passed.
  - `git diff --check` passed.
- `mlx-swift`:
  - `swift test --filter TurboQuantWave7PlatformPolicyTests` passed.
  - `swift test --filter 'TurboQuantContractsTests|TurboQuantValidationTests|TurboQuantAttentionRouterTests|TurboQuantBenchmarkReportTests'` passed.
  - `swift build` passed.
  - `git diff --check` passed.
  - Full `swift test` was blocked at Wave 7 handoff by the pre-existing Metal
    library compile failure in `MLXArrayIndexingTests.testFullIndexReadArray`:
    `general_reduce_looped` was undeclared while compiling
    `mlx/backend/metal/kernels/reduce.h`. The later production closeout
    regenerated the stale Metal reduce JIT source and full core tests passed on
    the final branch.

### Exit State

- Wave 7 platform contracts are implemented across Pines, `mlx-swift`, and
  `mlx-swift-lm`.
- All Wave 7 features remain disabled by default, kill-switched, and
  evidence-required.
- No Wave 7 product claim is promoted without real-device evidence, even after
  the compatibility pair becomes green.
- A later production closeout resolved the full local Xcode package/app
  validation blocker and marked `compatibility-pair.json` green for local
  release gates.
- The Wave 7 platform feature set remains disabled by default until
  feature-specific policy and evidence gates pass.

### Post-Audit Hardening

After the initial Wave 7 implementation commit, a deeper cross-repo audit found
several production-readiness gaps that were fixed before handoff:

- `mlx-swift`:
  - Made `TurboQuantKernelCapabilities` fully explicit for tiled fused support,
    supported head dimensions, selected kernel profile, and failure reasons.
  - Expanded `TurboQuantAttentionDecision` with the complete decision-ledger
    fields required by Pines: head dimension, query length, logical length,
    dtype, mask kind, kernel profile, and fallback reason.
  - Added `.unavailable` as an explicit attention-path outcome so unsupported
    requests do not masquerade as `.baseline` when no fallback is available.
  - Hardened the router so unsupported masks/shapes with no budgeted fallback
    fail closed as `.unavailable`.
  - Changed benchmark failure reporting so failed compressed-path attempts emit
    an unavailable decision instead of claiming the originally requested path.
  - Rejected invalid V4 benchmark combinations that request fp16 attention scale
    storage without opting into layout V5.
- Pines:
  - Added `.unavailable` to the local TurboQuant attention path enum.
  - Tightened product compatibility matching so `Verified`/`Certified` states
    require evidence from the active compatibility pair, preventing stale
    evidence from promoting product claims.
  - Replaced the test-only repeating-XOR snapshot cipher with authenticated
    AES-GCM sealing backed by deterministic local key material for the current
    store abstraction.
  - Fixed in-memory snapshot restore selection so a newer mismatched or
    corrupted snapshot no longer blocks restore from an older valid snapshot.
- `mlx-swift-lm`:
  - Made `MTPConfig.retainMTPWeights` lock-protected to remove the remaining
    process-wide race found by full LM test runs.

### Production Closeout

After Wave 7, the final release-green pass:

- pushed the `mlx-swift` and `mlx-swift-lm` release branches;
- regenerated the stale `mlx-swift` Metal reduce JIT source so full core tests
  pass;
- pinned `mlx-swift-lm` to the fixed core commit;
- promoted Pines to `mlx-swift`
  `21a897c5d1ae1930bd7c7a47bb3ed6c9fe8c8772` and `mlx-swift-lm`
  `6d2d791a12e60dc1bd7534d6c95454a2284edf8c`;
- fixed locked Xcode package validation for the final pair;
- passed `bash scripts/ci/run-xcode-validation.sh all`;
- updated `compatibility-pair.json` to `green` for local release gates.

This closeout does not create a real-device `Verified` or `Certified` model
claim. Those claims still require imported model/device/mode evidence from an
online iPhone-class device.
  - Updated `AGENTS.md` to match the current `Package.swift` MLX pin.

Additional post-audit validation:

- Pines:
  - `swift build --disable-automatic-resolution` passed.
  - `swift test --disable-automatic-resolution` passed with 189 tests.
  - `swift run --disable-automatic-resolution PinesCoreTestRunner` passed.
  - Focused Wave 3/Wave 7/snapshot tests passed.
  - `xcrun swiftc -parse` passed for the changed runtime and presentation app
    files.
  - `git diff --check` passed.
- `mlx-swift-lm`:
  - `swift build --target MLXLMCommon` passed.
  - Full `swift test --quiet` passed.
  - Focused Wave 7/MTP safety tests passed.
  - `git diff --check` passed.
- `mlx-swift`:
  - `swift build` passed.
  - Focused contract/router/benchmark tests passed.
  - V5 fp16-scale benchmark smoke emitted `onlineFused`, layout version `5`,
    and scale storage `float16`.
  - Invalid V4 fp16-scale benchmark options fail closed with an explicit
    configuration error.
  - `git diff --check` passed.
