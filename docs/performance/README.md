# Pines Performance Program

This directory is the source of truth for app responsiveness work. Performance changes are not accepted from code inspection alone: they require a Release/Profile build, a repeatable workload, retained evidence, and a comparison against the same device, OS, dataset, and build configuration.

## Goals

- Keep launch, tab changes, chat opening, Vault detail, and artifact browsing immediately responsive.
- Preserve fluid 60 Hz scrolling and take advantage of 120 Hz ProMotion hardware without scheduling avoidable work on the main actor.
- Keep memory proportional to visible or actively selected content, not total library size.
- Bound polling, provider refreshes, response bodies, uploads, image decoding, render caches, and database list queries.
- Degrade optional motion, haptics, prefetch, and caches under Low Power Mode, thermal pressure, reduced motion, backgrounding, or memory warnings.
- Prevent test-only diagnostics and benchmark helpers from entering the shipping binary.

## Acceptance Budgets

These are release goals, not claims about an unmeasured build. Record actual p50/p95 values in a dated baseline before marking a device class accepted.

| Journey | Acceptance goal |
| --- | --- |
| Warm launch to interactive | p95 at or below 1.0 s |
| Cold launch to interactive | p95 at or below 2.0 s |
| Existing chat to first visible message | p95 at or below 300 ms warm, 1.0 s cold |
| Artifact gallery to first thumbnail | p95 at or below 500 ms warm, 1.2 s cold |
| Vault row to useful detail | p95 at or below 300 ms warm, 800 ms cold |
| Local search response after debounce | p95 at or below 150 ms without a main-thread stall |
| Scrolling | no repeatable hitch above 33 ms; frames above 16.67 ms under 1% on the test journey |
| Image cache | decoded-image cost bounded to 64 MiB and purged on pressure |
| Main-thread file I/O | zero File Activity samples attributable to provider staging or preview decode |
| Shipping binary | no `TurboQuantBench` or `IntegrationTestHelpers` linkage |

For 120 Hz devices, inspect the 8.33 ms frame budget in Instruments as a quality signal. Do not fail a release solely on simulator frame pacing; simulator results are for regression detection, while device traces are the acceptance evidence.

## Implementation Map

- `PinesRuntimeMetrics` provides privacy-safe signpost intervals for launch, chat, gallery thumbnails, artifact derivation, provider polling, Vault detail, thumbnail decode, and provider transfer stages.
- `PinesImagePipeline` performs off-main ImageIO downsampling, request coalescing, generation-safe cancellation, and cost-bounded caching.
- `ArtifactActivityPollingScheduler` owns one structured polling loop per stable operation identity with cadence, backoff, jitter, and terminal-state exit.
- Provider lifecycle presentation is published as one atomic snapshot; repository reads are concurrent, SQL-capped and indexed, while mutation paths update only affected domains.
- Vault list rows are summaries. Selected detail loads one chunk page, aggregate counts, and a bounded source preview.
- Markdown, syntax highlighting, and citation metadata use content-keyed, cost-bounded caches and are purged under pressure.
- `PinesPerformancePolicy` centralizes reactive pressure-aware behavior for decorative motion, expressive haptics, cache eviction, and the gate future speculative prefetch consumers must use.
- `PinesPerformance` is the Release/Profile Xcode scheme. It disables coverage and does not link benchmark-only helper products.

See [ARCHITECTURE.md](ARCHITECTURE.md) for invariants, [RUNBOOK.md](RUNBOOK.md) for measurement, and [baselines/README.md](baselines/README.md) for evidence format.
