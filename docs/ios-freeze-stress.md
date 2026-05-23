# iOS Freeze Stress Diagnostics

Pines has a debug-only stress harness for the hard failure mode where local MLX generation stalls, the app stops producing output, or the device becomes unresponsive enough that normal UI controls cannot recover it.

## Customer Build Isolation

- The in-app runner lives behind `#if DEBUG`.
- Release, App Store, and TestFlight-style builds do not compile the launch hook or stress runner.
- Debug builds do nothing unless launched with `PINES_STRESS_MODE=local-generation` or `--pines-stress-local-generation`.
- Breadcrumb files are only written when `PINES_FREEZE_BREADCRUMBS=1`, stress mode is enabled, or the matching hidden launch argument is present.
- The harness writes diagnostics under the app sandbox at `Documents/PinesDiagnostics`; it does not add customer-facing UI, settings, or model behavior.

The customer-facing build still receives the runtime safety fixes that are meant to reduce real crashes and stalls: watchdog cancellation, transcript cleanup, stale run repair, thermal and memory safety gates, and local runtime unload on pressure.

## Running The Stress Harness

Connect a paired physical iPhone with Developer Mode enabled, install at least one local text model in Pines, then run:

```bash
bash scripts/diagnostics/run-ios-freeze-stress.sh
```

By default, the script preserves the already-installed app and its app container. This is intentional: replacing a development app on device can disturb large local model files stored in the app container. Set `PINES_STRESS_SKIP_INSTALL=0` only when you explicitly want the harness to build and reinstall the app, then reinstall or verify the local model before running stress.

The script:

1. Selects the first paired physical iOS device, unless `PINES_DEVICE_ID` is set.
2. Launches the already-installed app by default, preserving its local model container.
3. Optionally builds and installs the `Pines` scheme in Debug when `PINES_STRESS_SKIP_INSTALL=0`.
4. Launches hidden local-generation stress mode.
5. Polls device responsiveness through `devicectl`.
6. Pulls `Documents/PinesDiagnostics` from the app container.
7. On timeout or failure, collects `devicectl diagnose` and, by default, a device sysdiagnose unless failure diagnostics are disabled.

Artifacts are written to `artifacts/ios-freeze-stress-<timestamp>` unless `PINES_STRESS_ARTIFACTS` is set.

## Useful Environment Variables

```bash
PINES_DEVICE_ID=00008130-... \
PINES_STRESS_ITERATIONS=100 \
PINES_STRESS_TIMEOUT_SECONDS=14400 \
PINES_STRESS_MEMORY_WARNING_EVERY=6 \
bash scripts/diagnostics/run-ios-freeze-stress.sh
```

- `PINES_DEVICE_ID`: device identifier, UDID, serial number, or name accepted by `devicectl`.
- `PINES_STRESS_ITERATIONS`: local chat continuations to run. Default: `50`.
- `PINES_STRESS_BUILD_TIMEOUT_SECONDS`: maximum time allowed for the device Debug build before the harness fails. Default: `1800`.
- `PINES_STRESS_ITERATION_TIMEOUT_SECONDS`: per-generation timeout. Default: `180`.
- `PINES_STRESS_RECOVERY_COOLDOWN_SECONDS`: cooldown after recoverable local memory pressure before continuing stress. Default: `15`.
- `PINES_STRESS_CONTEXT_SWEEP`: set to `1` to grow each prompt toward the selected runtime context window and find the practical on-device boundary.
- `PINES_STRESS_CONTEXT_START_TOKENS`: approximate first prompt size when context sweep is enabled. Default: `1024`.
- `PINES_STRESS_CONTEXT_STEP_TOKENS`: approximate token increase per iteration when context sweep is enabled. Default: `2048`.
- `PINES_STRESS_CONTEXT_MAX_TOKENS`: optional sweep ceiling. Default: the runtime-selected local context window minus a small completion reserve.
- `PINES_STRESS_TIMEOUT_SECONDS`: total host-side timeout. Default: `7200`.
- `PINES_STRESS_POLL_SECONDS`: poll interval. Default: `10`.
- `PINES_STRESS_MEMORY_WARNING_EVERY`: send a memory warning every N polls. Default: `0`.
- `PINES_STRESS_SUSPEND_EVERY`: suspend/resume the app every N polls. Default: `0`.
- `PINES_STRESS_APP_PATH`: when reinstalling, install an already-built Debug `.app` instead of building.
- `PINES_STRESS_SKIP_INSTALL`: set to `1` to launch the already-installed Debug app without replacing its app container. Default: `1`.
- `PINES_STRESS_COLLECT_FAILURE_DIAGNOSTICS`: set to `0` to skip all CoreDevice failure diagnostics when you only need the app-written status files. Default: `1`.
- `PINES_STRESS_SYSDIAGNOSE_ON_FAILURE`: collect sysdiagnose on failure. Default: `1`.

## Reading Results

Primary files:

- `summary.json`: final host-side result and last app stress status.
- `app-diagnostics/pines-stress-status.json`: in-app state, iteration, model ID, and message.
- `app-diagnostics/pines-freeze-breadcrumbs.jsonl`: bounded event log from app launch, model loading, exact token preflight, selected context window, runtime pressure reason, Low Power state, TurboQuant profile source, token streaming, completion, cancellation, and unload.
- `devicectl-diagnose.zip`: host and CoreDevice diagnostics after failure.
- `sysdiagnose/`: device sysdiagnose when collection succeeds.

If the iPhone fully freezes, public automation cannot force a hardware recovery. The script detects the failure by bounded `devicectl` responsiveness probes and collects whatever diagnostics CoreDevice can still retrieve.
