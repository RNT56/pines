#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

scheme="${PINES_SCHEME:-Pines}"
configuration="${PINES_CONFIGURATION:-Debug}"
bundle_id="${PINES_BUNDLE_ID:-com.schtack.pines}"
derived_data_path="${PINES_DERIVED_DATA_PATH:-$root/build/DerivedDataFreezeStress}"
artifacts="${PINES_STRESS_ARTIFACTS:-$root/artifacts/ios-freeze-stress-$timestamp}"
run_id="${PINES_STRESS_RUN_ID:-freeze-stress-$timestamp}"
iterations="${PINES_STRESS_ITERATIONS:-50}"
iteration_timeout="${PINES_STRESS_ITERATION_TIMEOUT_SECONDS:-180}"
recovery_cooldown="${PINES_STRESS_RECOVERY_COOLDOWN_SECONDS:-15}"
overall_timeout="${PINES_STRESS_TIMEOUT_SECONDS:-7200}"
build_timeout="${PINES_STRESS_BUILD_TIMEOUT_SECONDS:-1800}"
poll_seconds="${PINES_STRESS_POLL_SECONDS:-10}"
device_poll_timeout="${PINES_STRESS_DEVICE_POLL_TIMEOUT_SECONDS:-15}"
memory_warning_every="${PINES_STRESS_MEMORY_WARNING_EVERY:-0}"
suspend_every="${PINES_STRESS_SUSPEND_EVERY:-0}"
sysdiagnose_on_failure="${PINES_STRESS_SYSDIAGNOSE_ON_FAILURE:-1}"
collect_diagnostics_on_failure="${PINES_STRESS_COLLECT_FAILURE_DIAGNOSTICS:-1}"
sysdiagnose_timeout="${PINES_STRESS_SYSDIAGNOSE_TIMEOUT_SECONDS:-900}"
skip_install="${PINES_STRESS_SKIP_INSTALL:-1}"
prompt="${PINES_STRESS_PROMPT:-Continue this local stress chat. Answer with a concise diagnostic paragraph and avoid tool use.}"
context_mode="${PINES_STRESS_CONTEXT_MODE:-${PINES_STRESS_CONTEXT_TEST:-}}"
if [ -z "$context_mode" ]; then
  if [ "${PINES_STRESS_CONTEXT_SWEEP:-0}" = "1" ]; then
    context_mode="sweep"
  else
    context_mode="off"
  fi
fi
context_start_tokens="${PINES_STRESS_CONTEXT_START_TOKENS:-1024}"
context_step_tokens="${PINES_STRESS_CONTEXT_STEP_TOKENS:-2048}"
context_max_tokens="${PINES_STRESS_CONTEXT_MAX_TOKENS:-}"
context_target_tokens="${PINES_STRESS_CONTEXT_TARGET_TOKENS:-}"
context_high_ratio="${PINES_STRESS_CONTEXT_HIGH_RATIO:-0.75}"
context_reserve_tokens="${PINES_STRESS_CONTEXT_RESERVE_TOKENS:-1024}"

mkdir -p "$artifacts/logs" "$artifacts/polls" "$artifacts/app-diagnostics"

log() {
  printf '[pines-freeze-stress] %s\n' "$*"
}

die() {
  log "error: $*"
  exit 1
}

if [ "$configuration" != "Debug" ]; then
  die "PINES_CONFIGURATION must be Debug. The in-app stress harness is compiled out of non-Debug builds."
fi

case "$context_mode" in
  off|sweep|high|max|suite) ;;
  *) die "PINES_STRESS_CONTEXT_MODE must be one of: off, sweep, high, max, suite." ;;
esac

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
  status_file="$(find "$artifacts/app-diagnostics" -name pines-stress-status.json -type f 2>/dev/null | head -n 1 || true)"
  python3 - "$artifacts/summary.json" "$result" "$reason" "$run_id" "$device_id" "$bundle_id" "${app_path:-}" "$status_file" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

summary_path, result, reason, run_id, device_id, bundle_id, app_path, status_file = sys.argv[1:]
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
  status_file="$(find "$artifacts/app-diagnostics" -name pines-stress-status.json -type f 2>/dev/null | head -n 1 || true)"
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

collect_failure_diagnostics() {
  local reason="$1"
  if [ "$collect_diagnostics_on_failure" != "1" ]; then
    log "Skipping failure diagnostics for $reason."
    return
  fi
  log "Collecting diagnostics after $reason."
  copy_app_diagnostics || true

  xcrun devicectl diagnose \
    --devices "$device_id" \
    --archive-destination "$artifacts/devicectl-diagnose.zip" \
    --no-finder \
    --timeout 600 \
    --json-output "$artifacts/devicectl-diagnose.json" \
    --quiet >"$artifacts/logs/devicectl-diagnose.log" 2>&1 || true

  if [ "$sysdiagnose_on_failure" = "1" ]; then
    mkdir -p "$artifacts/sysdiagnose"
    xcrun devicectl device sysdiagnose \
      --device "$device_id" \
      --destination "$artifacts/sysdiagnose" \
      --gather-full-logs \
      --timeout "$sysdiagnose_timeout" \
      --json-output "$artifacts/sysdiagnose.json" \
      --quiet >"$artifacts/logs/sysdiagnose.log" 2>&1 || true
  fi
}

app_path="${PINES_STRESS_APP_PATH:-}"
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
    "-allowProvisioningUpdates",
    "build",
]

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
        message = f"[pines-freeze-stress] error: xcodebuild exceeded {timeout_seconds}s build timeout.\n"
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
  [ -d "$app_path" ] || die "Unable to find built app bundle. Set PINES_STRESS_APP_PATH explicitly."
fi

if [ "$skip_install" = "1" ]; then
  log "Skipping install and launching the already-installed app."
else
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
    "$iterations" \
    "$iteration_timeout" \
    "$recovery_cooldown" \
    "$prompt" \
    "$context_mode" \
    "$context_start_tokens" \
    "$context_step_tokens" \
    "$context_max_tokens" \
    "$context_target_tokens" \
    "$context_high_ratio" \
    "$context_reserve_tokens" <<'PY'
import json
import sys

(
    run_id,
    iterations,
    iteration_timeout,
    recovery_cooldown,
    prompt,
    context_mode,
    context_start_tokens,
    context_step_tokens,
    context_max_tokens,
    context_target_tokens,
    context_high_ratio,
    context_reserve_tokens,
) = sys.argv[1:]
environment = {
    "PINES_FREEZE_BREADCRUMBS": "1",
    "PINES_STRESS_MODE": "local-generation",
    "PINES_STRESS_RUN_ID": run_id,
    "PINES_STRESS_ITERATIONS": iterations,
    "PINES_STRESS_ITERATION_TIMEOUT_SECONDS": iteration_timeout,
    "PINES_STRESS_RECOVERY_COOLDOWN_SECONDS": recovery_cooldown,
    "PINES_STRESS_PROMPT": prompt,
    "PINES_STRESS_RESET_BREADCRUMBS": "1",
    "PINES_STRESS_CONTEXT_MODE": context_mode,
    "PINES_STRESS_CONTEXT_START_TOKENS": context_start_tokens,
    "PINES_STRESS_CONTEXT_STEP_TOKENS": context_step_tokens,
    "PINES_STRESS_CONTEXT_HIGH_RATIO": context_high_ratio,
    "PINES_STRESS_CONTEXT_RESERVE_TOKENS": context_reserve_tokens,
}
if context_max_tokens:
    environment["PINES_STRESS_CONTEXT_MAX_TOKENS"] = context_max_tokens
if context_target_tokens:
    environment["PINES_STRESS_CONTEXT_TARGET_TOKENS"] = context_target_tokens
print(json.dumps(environment))
PY
)"

launch_json="$artifacts/launch.json"
log "Launching hidden local-generation stress mode, run $run_id, context mode $context_mode."
xcrun devicectl device process launch \
  --device "$device_id" \
  --terminate-existing \
  --activate \
  --environment-variables "$launch_environment" \
  --timeout 120 \
  --json-output "$launch_json" \
  --quiet \
  "$bundle_id" \
  --pines-stress-local-generation \
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
    collect_failure_diagnostics "device responsiveness probe failure"
    write_summary "failed" "device responsiveness probe failed"
    die "Device responsiveness probe failed. Artifacts: $artifacts"
  fi

  copy_app_diagnostics || true
  state="$(read_status_field state)"
  iteration="$(read_status_field iteration)"
  message="$(read_status_field message)"
  log "Poll $poll_index: state=${state:-unknown} iteration=${iteration:-unknown} message=${message:-none}"

  case "$state" in
    completed)
      copy_app_diagnostics || true
      write_summary "completed" "stress run completed"
      log "Stress run completed. Artifacts: $artifacts"
      exit 0
      ;;
    failed)
      collect_failure_diagnostics "in-app stress failure"
      write_summary "failed" "${message:-in-app stress failure}"
      die "Stress run failed. Artifacts: $artifacts"
      ;;
  esac

  if [ -n "$pid" ] && [ "$memory_warning_every" -gt 0 ] && [ $((poll_index % memory_warning_every)) -eq 0 ]; then
    log "Sending memory warning to PID $pid."
    xcrun devicectl device process sendMemoryWarning \
      --device "$device_id" \
      --pid "$pid" \
      --timeout 15 \
      --quiet >"$artifacts/logs/memory-warning-$poll_index.log" 2>&1 || true
  fi

  if [ -n "$pid" ] && [ "$suspend_every" -gt 0 ] && [ $((poll_index % suspend_every)) -eq 0 ]; then
    log "Suspending and resuming PID $pid."
    xcrun devicectl device process suspend \
      --device "$device_id" \
      --pid "$pid" \
      --timeout 15 \
      --quiet >"$artifacts/logs/suspend-$poll_index.log" 2>&1 || true
    sleep 2
    xcrun devicectl device process resume \
      --device "$device_id" \
      --pid "$pid" \
      --timeout 15 \
      --quiet >"$artifacts/logs/resume-$poll_index.log" 2>&1 || true
  fi

  sleep "$poll_seconds"
done

collect_failure_diagnostics "overall timeout"
write_summary "failed" "stress run exceeded ${overall_timeout}s"
die "Stress run exceeded ${overall_timeout}s. Artifacts: $artifacts"
