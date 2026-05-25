# Wave 6 Changelog

Read this alongside:

- `14-worker-launch-schedule.md`
- `15-pr-merge-plan.md`
- `08-worker-ownership.md`
- `12-validation-and-release-gates.md`
- `mlx-swift-lm/docs/turboquant-implementation/kv-snapshots-speculative.md`

This file tracks Wave 6 speculative decode and platform-unlock implementation after the completed Wave 5 optimization handoff.

## 2026-05-25

### Start State

- Pines Wave 6 branch: `tq/pines-speculative`.
- Pines branch base: `bde64e2` from `tq/wave5-optimization-evidence`.
- `mlx-swift-lm` Wave 6 branch: `tq/lm-speculative`.
- `mlx-swift-lm` branch base: `76eabed` from `tq/lm-wave5-validation`.
- `mlx-swift` remains at Wave 5 branch `tq/layout-v5-kernels` commit `741fa31`; no direct Core Wave 6 implementation is scheduled unless LM exposes a missing primitive.
- `compatibility-pair.json` remains `pending`; Wave 6 must not promote Verified/Certified product claims without a green compatibility pair and evidence.
- Full local Xcode package/app validation remains blocked by the known `xcodebuild -resolvePackageDependencies` stall.
- Pines had generated scheme drift in `Pines.xcodeproj/xcshareddata/xcschemes/Pines.xcscheme` and `PinesWatch.xcscheme` before Wave 6 implementation edits began.

### Wave 6 Scope

- W15A: `mlx-swift-lm` speculative verifier, rollback-safe TurboQuant compressed cache behavior, acceptance metrics, and tokenizer/draft compatibility surface.
- W15B: Pines Fast mode UX, speculative telemetry, poor-acceptance auto-disable, evidence dimensions, and admission/runtime metadata.
- Serialized bridge integration: wire LM speculative telemetry through Pines runtime only after the W15A/W15B contracts are stable.
- W29+: platform unlocks remain disabled design/schema gates unless explicitly activated by evidence and release gates.

### Constraints

- No product activation without accepted-token equivalence, rejected-token rollback proof, poor-acceptance disable behavior, and evidence-backed Fast mode improvement.
- Do not silently route local failures to cloud.
- Do not edit production pins, `project.yml`, `Package.resolved`, or generated Xcode project files for Wave 6.
- Keep Layout V5 opt-in; V4 remains default/current unless a later release gate explicitly changes that.
- Snapshot restore must not persist tentative or rejected speculative cache state.

### Progress

- Created this Wave 6 progress log before implementation edits.
- Created `mlx-swift-lm` branch `tq/lm-speculative`.
- Created Pines branch `tq/pines-speculative`.
- Launched parallel implementation workers for:
  - W15A LM speculative verifier and rollback support;
  - W15B Pines speculative DTO/evidence/UI/platform surfaces.
- Integrated and hardened the W15A worker patch:
  - added `TurboQuantSpeculative.swift` in `mlx-swift-lm` with target verifier helpers, rollback checkpoint metadata, rollback trim results, acceptance metrics, and tokenizer compatibility fingerprints;
  - wired speculative acceptance metrics into `GenerateCompletionInfo`;
  - changed the generation loop to consume the mutable iterator that actually emits tokens so completion metrics reflect the real run;
  - surfaced MTP speculative acceptance metrics through the same completion-info path;
  - overrode non-rotating `TurboQuantKVCache.trim(_:)` so compressed layout logical length, ring offset, pinned prefix, lifecycle, and transient bytes stay consistent after rejected-token rollback.
- Integrated and hardened the W15B worker patch:
  - added MLX-free Pines speculative DTOs for settings, evidence dimensions, runtime telemetry, auto-disable policy/decision, admission reserve budget, and disabled W29+ platform gates;
  - extended schema registry with `SpeculativeDecode.v1` and `PlatformFeatureGate.v1`;
  - threaded speculative dimensions and telemetry through benchmark reports, evidence import, evidence lookup, RunDecision, runtime profiles, diagnostics, provider metadata keys, and GRDB profile-evidence persistence;
  - added verified-evidence gates requiring tokenizer compatibility, target-sequence match, p50 decode speedup evidence, and no auto-disable decision;
  - reserved draft model, draft KV, and rollback memory in admission zones when speculative budget is enabled;
  - added model detail display for speculative state, draft model, acceptance rate, auto-disable reason, and disabled platform gates.
- Wired LM speculative acceptance metrics into Pines runtime metadata for explicit TurboQuant/speculative profiles, including per-run telemetry JSON and auto-disable decisions in `TurboQuantRunDecision`.
- Hardened the app runtime bridge helper visibility/call sites so the `MLXRuntimeState` actor references shared TurboQuant metadata helpers through `MLXRuntimeBridge` explicitly.
- Added focused tests:
  - LM `TurboQuantSpeculativeTests` for target verifier, poor-acceptance disable metrics, and non-rotating compressed-cache rollback layout;
  - LM `SpeculativeDecodingTests` now asserts speculative completion metrics are present and internally consistent while output still matches target generation;
  - LM `MTPTokenIteratorTests` now asserts MTP metrics;
  - Pines `TurboQuantWave6SpeculativeTests` covers telemetry roundtrip, poor-acceptance auto-disable, admission budget reserves, RunDecision target-mismatch safety, verified speculative evidence gates, exact speculative evidence tuple matching, and disabled W29+ platform gates;
  - schema/database tests now include Wave 6 schema names and `PinesDatabaseSchema.currentVersion == 22`.

### Validation

- `mlx-swift-lm`: `swift test --filter 'SpeculativeDecodingTests|TurboQuantSpeculativeTests|MTPTokenIteratorTests'` passed 10 Swift Testing tests.
- `mlx-swift-lm`: `swift test --filter 'SpeculativeDecodingTests|TurboQuantSpeculativeTests|MTPTokenIteratorTests|TurboQuant'` passed the focused TurboQuant/speculative set: 4 XCTest tests plus 93 Swift Testing tests.
- `mlx-swift-lm`: full `swift test` passed: XCTest phase plus 184 Swift Testing tests.
- Pines: `swift build` passed.
- Pines: `swift test --filter TurboQuantWave6SpeculativeTests` passed 6 Swift Testing tests.
- Pines: full `swift test` passed 182 Swift Testing tests.
- Pines: `swift test --disable-automatic-resolution` passed 182 Swift Testing tests.
- Pines: `swift run --disable-automatic-resolution PinesCoreTestRunner` passed.
- Pines: `bash scripts/ci/check-mlx-package-pins.sh` passed.
- `git diff --check` passed in `mlx-swift-lm`, `pines`, and unchanged `mlx-swift`.

### Non-Green / Deferred Gates

- `bash scripts/ci/run-xcode-validation.sh prepare && ... generate` still fails the generated-project drift check because pinned XcodeGen rewrites the two scheme files that were already dirty before Wave 6 began. The generated files were restored to the pre-validation snapshot so Wave 6 does not overwrite that pre-existing drift.
- Full Xcode package/app validation remains blocked by the known local `xcodebuild -resolvePackageDependencies` stall.
- Product activation remains disabled: speculative Fast mode requires imported verified evidence with target-match, tokenizer-compatible, no poor-acceptance auto-disable, and p50 decode speedup.
- W29+ platform features remain design/schema gates only; every default gate is disabled, kill-switched, and evidence-required.
