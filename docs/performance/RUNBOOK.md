# Performance Measurement Runbook

## Reproducible Setup

1. Record commit, device model, hardware identifier, OS build, battery/charging state, Low Power Mode, thermal state, free storage, dataset fixture, and network conditions.
2. Close unrelated apps and allow the device to return to nominal thermal state.
3. Generate the project with the pinned wrapper and build the `PinesPerformance` scheme.
4. Use the same warm/cold-cache protocol for both compared commits. Run at least five measured repetitions after one warm-up.
5. Retain the `.trace`, `.xcresult`, console/build log, and a completed baseline template.

```sh
bash scripts/ci/xcodegen.sh generate
bash scripts/ci/check-release-build-hygiene.sh
bash scripts/diagnostics/run-ios-ui-performance.sh
```

The UI harness is a regression signal. Final scrolling and memory acceptance requires a physical-device Instruments trace.

The harness builds an optimized simulator slice and enables a simulator-only deterministic fixture. The Release device/App Store slice does not compile that fixture path. Use the harness for repeatable regression comparison, not as physical-device acceptance.
Its `environment.txt` records the commit, worktree state, Xcode, host OS, destination, and iteration count; a dirty-worktree capture is labeled provisional and must not become release acceptance evidence.

Set `PINES_PERFORMANCE_DESTINATION` to an explicit xcodebuild destination and `PINES_PERFORMANCE_ITERATIONS` to the measured repetition count when the defaults are unsuitable. The harness records both values, forces `ONLY_ACTIVE_ARCH=YES` for the selected simulator, and rejects non-integer iteration counts.

```sh
PINES_PERFORMANCE_DESTINATION='id=<simulator-udid>' \
PINES_PERFORMANCE_ITERATIONS=5 \
bash scripts/diagnostics/run-ios-ui-performance.sh
```

```sh
xcodebuild \
  -project Pines.xcodeproj \
  -scheme PinesPerformance \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

For device profiling, select `PinesPerformance`, choose Product > Profile, and capture these templates:

- App Launch for cold and warm launch.
- Animation Hitches for Chats, Artifacts, and Vault scrolling.
- Time Profiler for the same journeys, with main-thread and Swift concurrency tracks visible.
- Allocations plus VM Tracker while opening 100 artifact thumbnails and repeatedly entering/leaving Vault details.
- File Activity during provider staging/upload and image preview.
- Network during provider polling and transfer retry/cancel.

## Canonical Journeys

### Launch

- Terminate Pines.
- Cold: reboot or install a fresh build before the first run when practical.
- Warm: launch once, terminate, then measure subsequent launches.
- End at the `launch_to_interactive` signpost.

### Chat

- Seed a 256-message thread containing plain text, Markdown, code blocks, and citations.
- Open the thread, scroll top-to-bottom, switch away, and reopen.
- Inspect `thread_to_first_message`, main-thread JSON/Markdown work, allocations, and hitch distribution.

### Artifacts

- Seed at least 500 mixed artifacts and 20 active/terminal operations.
- Open the gallery cold and warm, type a search query, change scope, scroll through 100 cells, open/close preview, and leave the screen idle for two minutes.
- Inspect `artifact_library_derive`, `gallery_to_first_thumbnail`, `thumbnail_decode`, poll request count, cache cost, and task count.

### Vault

- Seed a document with at least 10,000 chunks plus embeddings and a 30 MiB image source.
- Open the list, enter detail, preview, export consent, leave detail, and trigger a simulated memory warning.
- Inspect `vault_detail_ready`, SQL query plans, retained chunk/embedding objects, image decode size, and post-warning memory.

### Provider lifecycle and transfer

- Seed each lifecycle table with at least 1,000 rows.
- Refresh all once, then create/update/delete one record in each domain.
- Stage and upload a large local file; cancel once and retry once.
- Inspect `provider_lifecycle_refresh`, `provider_poll_cycle`, `transfer_stage`, `transfer_enqueued`, repository query count, main-thread File Activity, peak resident memory, and progress-write frequency.

## Regression Rules

- Compare p50 and p95, not the single fastest run.
- Investigate a p95 latency regression above 10%, a peak-memory regression above 10%, any new repeatable hitch above 33 ms, any new main-thread file/decode work, or any unbounded query/cache behavior.
- Do not merge a threshold change in the same commit that causes the regression unless the baseline document explains the intentional product tradeoff.
- Simulator-only improvements are provisional. Record them as regression evidence, not real-device acceptance.
- A thermal or memory-pressure failure is a correctness failure even when the median timing improves.

## Triage Order

1. Confirm Release/Profile configuration and exact dependency graph.
2. Confirm the fixture and cache state match the comparison run.
3. Locate the signpost interval and identify whether time is main-thread, database, filesystem, network, decode, or rendering.
4. Check duplicate tasks, unstable task identities, refresh fan-out, and retained detail/cache state.
5. Form one hypothesis, change one boundary, and rerun the canonical journey.
6. Preserve the before/after evidence and update the baseline ledger.
