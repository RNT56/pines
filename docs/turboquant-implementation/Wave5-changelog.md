# Wave 5 Changelog

Read this alongside:

- `14-worker-launch-schedule.md`
- `15-pr-merge-plan.md`
- `08-worker-ownership.md`
- `06-quality-gates.md`
- `07-benchmark-evidence.md`
- `12-validation-and-release-gates.md`
- `mlx-swift/docs/turboquant-implementation/layout-v5-kernels.md`

This file tracks Wave 5 optimization implementation after the completed Wave 4 context and persistence handoff.

Current closeout note: a later production pass regenerated the stale
`mlx-swift` Metal reduce JIT source, so full core tests now pass. The final
compatibility pair is green for local release gates, while Layout V5 and
optimization claims remain evidence-gated and real-device tuple dependent.

## 2026-05-25

### Start State

- Pines Wave 5 branch: `tq/wave5-optimization-evidence`.
- Pines branch base: `f001c8a` from `tq/wave4-context-persistence`.
- `mlx-swift` Wave 5 branch: `tq/layout-v5-kernels`.
- `mlx-swift` branch base: `6a5d5d8` from `tq/core-benchmark-json`.
- `mlx-swift-lm` Wave 5 validation branch: `tq/lm-wave5-validation`.
- `mlx-swift-lm` branch base: `76eabed` from `tq/lm-kv-snapshots`.
- `compatibility-pair.json` remained `pending` at Wave 5 start; Wave 5 could
  not promote Verified/Certified product claims without a green compatibility
  pair and evidence.
- At Wave 5 start, full Xcode package/app validation was blocked by the known local `xcodebuild -resolvePackageDependencies` stall. A later production closeout resolved this local gate.

### Wave 5 Scope

- W13: `mlx-swift` Layout V5, kernel warmup, fused specializations, hidden-copy audit, and benchmark evidence.
- Optimization evidence update: before/after V4/V5 benchmark evidence, QualityGate preservation, memory calibration preservation, and exact-tuple gating in Pines.
- LM validation sidecar: confirm profile, benchmark, cache, and snapshot behavior against a W13 candidate without changing product activation.

### Constraints

- Layout V5 must remain feature-gated and off by default.
- V4 layout compatibility must remain intact.
- Unsupported dimensions must fall back safely or produce typed rejected-path reasons before Metal dispatch.
- Hidden full-cache K/V copies remain release-blocking.
- QualityGate must remain green for any optimization claim.
- No production pin promotion in Wave 5.
- Do not edit `project.yml`, `Package.resolved`, or Pines production pins from Wave 5 worker branches.
- Generated Xcode scheme normalization may be retained only when it is produced by the required XcodeGen validation cycle and no production pin files change.

### Progress

- Created Wave 5 branches from the clean Wave 4 handoff heads.
- Created this Wave 5 progress log before implementation edits.
- Launched parallel read-only planning workers for:
  - core W13 optimization branch port/audit;
  - Pines exact-tuple evidence and UI implications;
  - LM validation and snapshot/profile compatibility.

### Implementation Progress

- W13 core:
  - added an opt-in `TurboQuantAttentionLayout.nextVersion == 5` while keeping V4 as the default/current write layout;
  - added V5-only fp16 attention scale storage support and storage-estimate accounting;
  - hardened empty-code allocation so manually constructed V5 layouts still require explicit V5 opt-in;
  - kept legacy `TurboQuantConfiguration` decoding compatible by defaulting missing Wave 5 fields to V4 behavior;
  - kept V4 validation strict to float32 scale storage while allowing V5 to validate float16 or float32 scales;
  - added benchmark JSON fields for `layoutVersion`, `scaleStorage`, and warmup iterations;
  - kept `TurboQuantHiddenCopyAudit.currentW3` stable and added `currentW5` for Layout V5 fp16 scale-table coverage;
  - added tests for V5 opt-in, V5 fp16 scale validation, V4 rejection of fp16 scales, and V5 storage savings.
- Pines evidence:
  - benchmark import policy now requires an accepted layout version before Verified/Certified evidence can be imported;
  - core benchmark JSON adapter carries `layoutVersion`, `scaleStorage`, and warmup metadata from the core report;
  - runtime profiles expose the active TurboQuant layout version for exact tuple matching;
  - profile-evidence lookup and claim-capable UI matching include layout version, fallback hash, preset, value bits, group size, and attention path;
  - model runtime details now display the matched evidence tuple and fallback-contract hash;
  - app-side product-claim evidence matching derives the fallback-contract hash from the request admission memory reserve/default mode reserve and no longer depends on a non-existent admission fallback-contract field.
- LM validation worker reported no LM code changes are required while V5 remains opt-in and `TurboQuantAttentionLayout.currentVersion` remains V4.

### Benchmark Smoke Evidence

- `mlx-swift` V4 default CLI smoke:
  - command: `swift run TurboQuantBenchmark --json --iterations 1 --warmup 1 --context 64 --head-dim 128 --query-length 1`;
  - selected path: `onlineFused`;
  - layout: `4`, scale storage: `float32`;
  - compressed KV bytes: `23556`;
  - storage estimate scale bytes: `5120`;
  - hidden-copy audit: `pass`.
- `mlx-swift` V5 opt-in CLI smoke:
  - command: `swift run TurboQuantBenchmark --json --iterations 1 --warmup 1 --context 64 --head-dim 128 --query-length 1 --layout-version 5 --enable-layout-v5 --scale-storage float16`;
  - selected path: `onlineFused`;
  - layout: `5`, scale storage: `float16`;
  - compressed KV bytes: `20996`;
  - storage estimate scale bytes: `2560`;
  - hidden-copy audit: `pass`.
- The CLI smoke evidence is implementation evidence only. `compatibility-pair.json` remains `pending`; no Verified/Certified claim or pin promotion was made.

### Validation Progress

- `mlx-swift`:
  - `swift test --filter TurboQuantValidationTests` passed 7 tests;
  - `swift test --filter TurboQuantBenchmarkReportTests` passed 5 tests;
  - `swift test --filter TurboQuantContractsTests` passed 6 tests;
  - `swift test --filter QuantizationTests` passed 53 tests;
  - `swift build --target TurboQuantBenchmark` passed;
  - full `swift test` was non-green at Wave 5 handoff because
    `MLXArrayIndexingTests.testFullIndexReadArray` tripped an existing Metal
    library build failure in `reduce.h`
    (`general_reduce_looped_5_reduce_sumint32`), before any Wave 5 tests were
    involved. The later production closeout regenerated the stale Metal reduce
    JIT source and full core tests passed on the final branch.
- Pines:
  - `swift build --disable-automatic-resolution` passed;
  - `swift test --disable-automatic-resolution --filter TurboQuantWave3EvidenceTests` passed 15 tests;
  - full `swift test --disable-automatic-resolution` passed 176 tests;
  - `swift run --disable-automatic-resolution PinesCoreTestRunner` passed;
  - changed app files parsed with `xcrun swiftc -parse`;
  - `scripts/ci/check-mlx-package-pins.sh` passed;
  - `python3 -m json.tool` passed for `compatibility-pair.json` and `compatibility-pair.schema.json`;
  - `scripts/ci/xcodegen.sh generate` passed;
  - `scripts/ci/run-xcode-validation.sh prepare`, `generate`, and `finalize` passed;
  - generated Xcode scheme normalization is retained from the validation cycle; `project.yml`, `Package.resolved`, and compatibility-pair state were not promoted.
- `mlx-swift-lm`:
  - `swift build --target MLXLMCommon` passed;
  - `swift test --filter TurboQuant` passed the TurboQuant-focused runtime/snapshot/profile set;
  - full `swift test` passed: 115 XCTest tests plus 181 Swift Testing tests.
- Hygiene:
  - `git diff --check` passed in `mlx-swift`, `pines`, and `mlx-swift-lm`.
- Wave 5 handoff non-green gate, later resolved:
  - `xcodebuild -resolvePackageDependencies -project Pines.xcodeproj -scheme Pines` stalled locally at handoff; the production closeout later passed `bash scripts/ci/run-xcode-validation.sh all` on the final pair.
