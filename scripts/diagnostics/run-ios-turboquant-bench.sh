#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

scheme="${PINES_SCHEME:-Pines}"
configuration="${PINES_CONFIGURATION:-Debug}"
bundle_id="${PINES_BUNDLE_ID:-com.schtack.pines}"
derived_data_path="${PINES_TQ_BENCH_DERIVED_DATA_PATH:-$root/build/DerivedDataTurboQuantBench}"
artifacts="${PINES_TQ_BENCH_ARTIFACTS:-$root/artifacts/ios-turboquant-bench-$timestamp}"
run_id="${PINES_TQ_BENCH_RUN_ID:-turboquant-bench-$timestamp}"
contexts="${PINES_TQ_BENCH_CONTEXTS:-}"
schemes="${PINES_TQ_BENCH_SCHEMES:-}"
runtime_modes="${PINES_TQ_BENCH_RUNTIME_MODES:-}"
precision_policies="${PINES_TQ_BENCH_PRECISION_POLICIES:-}"
sparse_v="${PINES_TQ_BENCH_SPARSE_V:-}"
full_matrix="${PINES_TQ_BENCH_FULL:-0}"
iterations="${PINES_TQ_BENCH_ITERATIONS:-}"
warmup="${PINES_TQ_BENCH_WARMUP:-}"
wave6_api="${PINES_TQ_BENCH_WAVE6_API:-0}"
overall_timeout="${PINES_TQ_BENCH_TIMEOUT_SECONDS:-1800}"
build_timeout="${PINES_TQ_BENCH_BUILD_TIMEOUT_SECONDS:-1800}"
poll_seconds="${PINES_TQ_BENCH_POLL_SECONDS:-5}"
device_poll_timeout="${PINES_TQ_BENCH_DEVICE_POLL_TIMEOUT_SECONDS:-15}"
skip_install="${PINES_TQ_BENCH_SKIP_INSTALL:-0}"
pines_commit="$(git -C "$root" rev-parse HEAD 2>/dev/null || true)"

mkdir -p "$artifacts/logs" "$artifacts/polls" "$artifacts/app-diagnostics"

log() {
  printf '[pines-turboquant-bench] %s\n' "$*"
}

die() {
  log "error: $*"
  exit 1
}

if [ "$configuration" != "Debug" ]; then
  die "PINES_CONFIGURATION must be Debug. The in-app TurboQuant benchmark harness is compiled out of non-Debug builds."
fi

select_device() {
  local devices_json="$artifacts/devices.json"
  xcrun devicectl list devices --json-output "$devices_json" --quiet >/dev/null
  python3 - "$devices_json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

devices = payload.get("result", {}).get("devices", [])
for device in devices:
    hardware = device.get("hardwareProperties", {})
    connection = device.get("connectionProperties", {})
    if (
        hardware.get("platform") == "iOS"
        and hardware.get("reality") == "physical"
        and connection.get("pairingState") == "paired"
    ):
        print(device.get("identifier") or hardware.get("udid") or "")
        break
PY
}

device_id="${PINES_DEVICE_ID:-}"
if [ -z "$device_id" ]; then
  device_id="$(select_device)"
fi
[ -n "$device_id" ] || die "No paired physical iOS device found. Set PINES_DEVICE_ID to choose one."

write_summary() {
  local result="$1"
  local reason="$2"
  local status_file
  local result_file
  status_file="$(find "$artifacts/app-diagnostics" -name pines-turboquant-bench-status.json -type f 2>/dev/null | head -n 1 || true)"
  result_file="$(find "$artifacts/app-diagnostics" -name "pines-turboquant-bench-$run_id.json" -type f 2>/dev/null | head -n 1 || true)"
  python3 - "$artifacts/summary.json" "$result" "$reason" "$run_id" "$device_id" "$bundle_id" "${app_path:-}" "$status_file" "$result_file" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

summary_path, result, reason, run_id, device_id, bundle_id, app_path, status_file, result_file = sys.argv[1:]
status = None
if status_file and os.path.exists(status_file):
    with open(status_file, "r", encoding="utf-8") as handle:
        status = json.load(handle)

summary = {
    "result": result,
    "reason": reason,
    "runID": run_id,
    "deviceID": device_id,
    "bundleID": bundle_id,
    "appPath": app_path or None,
    "status": status,
    "resultFile": result_file or None,
    "updatedAt": datetime.now(timezone.utc).isoformat(),
}
with open(summary_path, "w", encoding="utf-8") as handle:
    json.dump(summary, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

copy_app_diagnostics() {
  local copy_json="$artifacts/logs/copy-app-diagnostics.json"
  local copy_log="$artifacts/logs/copy-app-diagnostics.log"
  xcrun devicectl device copy from \
    --device "$device_id" \
    --domain-type appDataContainer \
    --domain-identifier "$bundle_id" \
    --source Documents/PinesDiagnostics \
    --destination "$artifacts/app-diagnostics" \
    --remove-existing-content true \
    --timeout 30 \
    --json-output "$copy_json" \
    --quiet >"$copy_log" 2>&1
}

read_status_field() {
  local field="$1"
  local status_file
  status_file="$(find "$artifacts/app-diagnostics" -name pines-turboquant-bench-status.json -type f 2>/dev/null | head -n 1 || true)"
  if [ -z "$status_file" ]; then
    printf ''
    return
  fi
  python3 - "$status_file" "$field" "$run_id" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)
if payload.get("runID") != sys.argv[3]:
    print("")
    raise SystemExit(0)
value = payload.get(sys.argv[2], "")
print("" if value is None else value)
PY
}

app_process_alive() {
  local probe_json="$1"
  local probe_log="$2"
  [ -n "$pid" ] || return 0
  xcrun devicectl device process signal \
    --device "$device_id" \
    --pid "$pid" \
    --signal 0 \
    --timeout 15 \
    --json-output "$probe_json" \
    --quiet >"$probe_log" 2>&1
}

app_path="${PINES_TQ_BENCH_APP_PATH:-}"
if [ "$skip_install" = "1" ]; then
  log "Preserving the installed app and local model container; skipping build and install."
else
  if [ -z "$app_path" ]; then
    log "Building $scheme Debug for device $device_id."
    python3 - "$artifacts/logs/xcodebuild.log" "$build_timeout" "$root/Pines.xcodeproj" "$scheme" "$configuration" "$device_id" "$derived_data_path" <<'PY'
import os
import selectors
import signal
import subprocess
import sys
import time

log_path, timeout_seconds, project_path, scheme, configuration, device_id, derived_data_path = sys.argv[1:]
timeout_seconds = int(timeout_seconds)
command = [
    "xcodebuild",
    "-project", project_path,
    "-scheme", scheme,
    "-configuration", configuration,
    "-destination", f"platform=iOS,id={device_id}",
    "-derivedDataPath", derived_data_path,
    "-skipMacroValidation",
    "-skipPackagePluginValidation",
    "-onlyUsePackageVersionsFromResolvedFile",
    "-disableAutomaticPackageResolution",
    "-scmProvider", "system",
    "-allowProvisioningUpdates",
    "build",
]
if os.environ.get("PINES_TQ_BENCH_WAVE6_API") == "1":
    command.insert(-1, "OTHER_SWIFT_FLAGS=$(inherited) -DPINES_TQ_BENCH_WAVE6_API")

deadline = time.monotonic() + timeout_seconds
timed_out = False
with open(log_path, "w", encoding="utf-8", errors="replace") as log:
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        start_new_session=True,
    )
    assert process.stdout is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)

    while process.poll() is None:
        if time.monotonic() > deadline:
            timed_out = True
            break
        for key, _ in selector.select(timeout=1):
            line = key.fileobj.readline()
            if not line:
                continue
            sys.stdout.write(line)
            sys.stdout.flush()
            log.write(line)
            log.flush()

    if timed_out:
        message = f"[pines-turboquant-bench] error: xcodebuild exceeded {timeout_seconds}s build timeout.\n"
        sys.stdout.write(message)
        sys.stdout.flush()
        log.write(message)
        log.flush()
        try:
            os.killpg(process.pid, signal.SIGINT)
            process.wait(timeout=10)
        except Exception:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except Exception:
                pass
        sys.exit(124)

    for remaining in process.stdout:
        sys.stdout.write(remaining)
        log.write(remaining)

    sys.exit(process.returncode or 0)
PY
    app_path="$derived_data_path/Build/Products/${configuration}-iphoneos/pines.app"
  fi

  if [ ! -d "$app_path" ]; then
    fallback_app_path="$(find "$derived_data_path/Build/Products" -name pines.app -type d 2>/dev/null | head -n 1 || true)"
    [ -n "$fallback_app_path" ] && app_path="$fallback_app_path"
  fi
  [ -d "$app_path" ] || die "Unable to find built app bundle. Set PINES_TQ_BENCH_APP_PATH explicitly."

  log "Installing $app_path."
  xcrun devicectl device install app \
    --device "$device_id" \
    --timeout 300 \
    --json-output "$artifacts/install.json" \
    --quiet \
    "$app_path" >"$artifacts/logs/install.log" 2>&1
fi

launch_environment="$(
  python3 - \
    "$run_id" \
    "$contexts" \
    "$schemes" \
    "$runtime_modes" \
    "$precision_policies" \
    "$sparse_v" \
    "$full_matrix" \
    "$iterations" \
    "$warmup" \
    "$device_id" \
    "$pines_commit" <<'PY'
import json
import sys

run_id, contexts, schemes, runtime_modes, precision_policies, sparse_v, full_matrix, iterations, warmup, device_id, pines_commit = sys.argv[1:]
environment = {
    "PINES_FREEZE_BREADCRUMBS": "1",
    "PINES_TURBOQUANT_BENCH": "1",
    "PINES_TQ_BENCH_RUN_ID": run_id,
    "PINES_TQ_BENCH_FULL": full_matrix,
    "PINES_TQ_BENCH_DEVICE_ID": device_id,
}
if pines_commit:
    environment["PINES_TQ_BENCH_PINES_COMMIT"] = pines_commit
if contexts:
    environment["PINES_TQ_BENCH_CONTEXTS"] = contexts
if schemes:
    environment["PINES_TQ_BENCH_SCHEMES"] = schemes
if runtime_modes:
    environment["PINES_TQ_BENCH_RUNTIME_MODES"] = runtime_modes
if precision_policies:
    environment["PINES_TQ_BENCH_PRECISION_POLICIES"] = precision_policies
if sparse_v:
    environment["PINES_TQ_BENCH_SPARSE_V"] = sparse_v
if iterations:
    environment["PINES_TQ_BENCH_ITERATIONS"] = iterations
if warmup:
    environment["PINES_TQ_BENCH_WARMUP"] = warmup
print(json.dumps(environment))
PY
)"

launch_json="$artifacts/launch.json"
log "Launching hidden TurboQuant benchmark mode, run $run_id."
xcrun devicectl device process launch \
  --device "$device_id" \
  --terminate-existing \
  --activate \
  --environment-variables "$launch_environment" \
  --timeout 120 \
  --json-output "$launch_json" \
  --quiet \
  "$bundle_id" \
  --pines-turboquant-bench \
  --pines-freeze-breadcrumbs >"$artifacts/logs/launch.log" 2>&1

pid="$(
  python3 - "$launch_json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

def walk(value):
    if isinstance(value, dict):
        for key in ("processIdentifier", "pid"):
            found = value.get(key)
            if isinstance(found, int):
                return found
        for child in value.values():
            found = walk(child)
            if found is not None:
                return found
    elif isinstance(value, list):
        for child in value:
            found = walk(child)
            if found is not None:
                return found
    return None

pid = walk(payload)
print("" if pid is None else pid)
PY
)"
[ -n "$pid" ] && log "Launched process PID $pid."

deadline=$((SECONDS + overall_timeout))
poll_index=0
while [ "$SECONDS" -lt "$deadline" ]; do
  poll_index=$((poll_index + 1))
  poll_json="$artifacts/polls/device-$poll_index.json"
  if ! xcrun devicectl device info details \
    --device "$device_id" \
    --timeout "$device_poll_timeout" \
    --json-output "$poll_json" \
    --quiet >"$artifacts/logs/device-poll-$poll_index.log" 2>&1; then
    copy_app_diagnostics || true
    write_summary "failed" "device responsiveness probe failed"
    die "Device responsiveness probe failed. Artifacts: $artifacts"
  fi

  copy_app_diagnostics || true
  state="$(read_status_field state)"
  result_count="$(read_status_field resultCount)"
  failed_count="$(read_status_field failedCount)"
  message="$(read_status_field message)"
  log "Poll $poll_index: state=${state:-unknown} results=${result_count:-0} failed=${failed_count:-0} message=${message:-none}"

  case "$state" in
    completed)
      copy_app_diagnostics || true
      write_summary "completed" "benchmark completed"
      log "Benchmark completed. Artifacts: $artifacts"
      exit 0
      ;;
    failed)
      copy_app_diagnostics || true
      write_summary "failed" "${message:-in-app benchmark failure}"
      die "Benchmark failed. Artifacts: $artifacts"
      ;;
  esac

  if [ -n "$pid" ] && ! app_process_alive "$artifacts/polls/process-$poll_index.json" "$artifacts/logs/process-probe-$poll_index.log"; then
    copy_app_diagnostics || true
    write_summary "failed" "app process $pid exited before the benchmark completed"
    die "App process $pid exited before the benchmark completed. Artifacts: $artifacts"
  fi

  sleep "$poll_seconds"
done

copy_app_diagnostics || true
write_summary "failed" "benchmark exceeded ${overall_timeout}s"
die "Benchmark exceeded ${overall_timeout}s. Artifacts: $artifacts"
