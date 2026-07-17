#!/usr/bin/env bash
set -euo pipefail

PINES_ROOT="${PINES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
MLX_FORKS_ROOT="${MLX_FORKS_ROOT:-/Users/mt/Programming/Schtack/mlx-forks}"
RUN_ID="${WAVE0_RUN_ID:-turboquant-wave0-$(date -u +%Y%m%dT%H%M%SZ)}"
MLX_ARTIFACTS="${WAVE0_MLX_ARTIFACTS:-$MLX_FORKS_ROOT/artifacts/$RUN_ID}"
PINES_ARTIFACTS="${WAVE0_PINES_ARTIFACTS:-$PINES_ROOT/artifacts/$RUN_ID}"
EVENTS_FILE="$MLX_ARTIFACTS/validation-events.jsonl"

mkdir -p "$MLX_ARTIFACTS"/{logs,benchmarks/default,benchmarks/coop,repo-state} "$PINES_ARTIFACTS"/{logs,repo-state}

log() {
  printf '[wave0] %s\n' "$*"
}

iso_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

json_event() {
  local repo="$1"
  local command="$2"
  local result="$3"
  local notes="$4"
  local artifact="$5"
  local started="$6"
  local finished="$7"
  python3 - "$EVENTS_FILE" "$repo" "$command" "$result" "$notes" "$artifact" "$RUN_ID" "$started" "$finished" <<'PY'
import json
import sys

path, repo, command, result, notes, artifact, run_id, started, finished = sys.argv[1:]
event = {
    "repo": repo,
    "command": command,
    "result": result,
    "notes": notes,
    "artifactPath": artifact,
    "runID": run_id,
    "startedAt": started,
    "finishedAt": finished,
}
with open(path, "a", encoding="utf-8") as handle:
    handle.write(json.dumps(event, sort_keys=True) + "\n")
PY
}

run_logged() {
  local repo_name="$1"
  local repo_path="$2"
  local label="$3"
  local command="$4"
  local log_file="$MLX_ARTIFACTS/logs/${repo_name}-${label}.log"
  local started finished result notes
  started="$(iso_now)"
  log "Running [$repo_name] $command"
  set +e
  (cd "$repo_path" && bash -lc "$command") >"$log_file" 2>&1
  local exit_code=$?
  set -e
  finished="$(iso_now)"
  if [ "$exit_code" -eq 0 ]; then
    result="passed"
    notes="Command completed."
  else
    result="failed"
    notes="Command exited with status $exit_code."
  fi
  json_event "$repo_name" "$command" "$result" "$notes" "$log_file" "$started" "$finished"
  return 0
}

run_json_benchmark() {
  local mode="$1"
  local preset="$2"
  local context="$3"
  local env_prefix="$4"
  local bench="$MLX_FORKS_ROOT/mlx-swift/.build/release/TurboQuantBenchmark"
  local out_dir="$MLX_ARTIFACTS/benchmarks/$mode"
  local json_file="$out_dir/core-${preset}-${context}.json"
  local log_file="$out_dir/core-${preset}-${context}.log"
  local command="${env_prefix}${bench} --json --iterations ${WAVE0_BENCH_ITERATIONS:-12} --warmup ${WAVE0_BENCH_WARMUP:-3} --context $context --preset $preset --head-dim 256 --query-heads 16 --kv-heads 4 --query-length 1"
  local started finished result notes
  started="$(iso_now)"
  log "Benchmark [$mode] preset=$preset context=$context"
  set +e
  (cd "$MLX_FORKS_ROOT/mlx-swift" && bash -lc "$command") >"$json_file" 2>"$log_file"
  local exit_code=$?
  python3 -m json.tool "$json_file" >/dev/null 2>>"$log_file"
  local json_code=$?
  set -e
  finished="$(iso_now)"
  if [ "$exit_code" -eq 0 ] && [ "$json_code" -eq 0 ]; then
    result="passed"
    notes="Benchmark emitted valid JSON."
  else
    result="failed"
    notes="Benchmark failed with exit=$exit_code json_validation=$json_code."
  fi
  json_event "mlx-swift" "$command" "$result" "$notes" "$json_file" "$started" "$finished"
}

record_repo_state() {
  python3 - "$MLX_FORKS_ROOT" "$PINES_ROOT" "$MLX_ARTIFACTS/repo-state.json" "$PINES_ARTIFACTS/repo-state.json" <<'PY'
import json
import os
import pathlib
import subprocess
import sys

mlx_root = pathlib.Path(sys.argv[1])
pines_root = pathlib.Path(sys.argv[2])
mlx_out = pathlib.Path(sys.argv[3])
pines_out = pathlib.Path(sys.argv[4])
repos = [
    ("mlx", mlx_root / "mlx"),
    ("mlx-c", mlx_root / "mlx-c"),
    ("mlx-swift", mlx_root / "mlx-swift"),
    ("mlx-swift-lm", mlx_root / "mlx-swift-lm"),
    ("pines", pines_root),
]

def run(repo, args):
    try:
        return subprocess.check_output(["git", "-C", str(repo), *args], text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""

def package_pins(root):
    pins = {}
    project = root / "project.yml"
    if project.exists():
        lines = project.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines):
            stripped = line.strip()
            if stripped in ("MLXSwift:", "MLXSwiftLM:"):
                for child in lines[index + 1:]:
                    child_stripped = child.strip()
                    if child_stripped.startswith("revision:"):
                        pins[stripped[:-1]] = child_stripped.replace("revision:", "").strip()
                        break
                    if child and not child.startswith("    "):
                        break
    compat = root / "docs/turboquant-implementation/compatibility-pair.json"
    if compat.exists():
        try:
            data = json.loads(compat.read_text(encoding="utf-8"))
            promotion = data.get("productionPinPromotion") or {}
            pins["compatibilityPairID"] = promotion.get("compatibilityPairID")
            pins["compatibilityStatus"] = data.get("status")
        except Exception as exc:
            pins["compatibilityPairError"] = str(exc)
    return pins

states = []
for name, repo in repos:
    status = run(repo, ["status", "--short"])
    dirty_files = []
    untracked_dirs = []
    for line in status.splitlines():
        path = line[3:] if len(line) > 3 else line
        if line.startswith("?? ") and path.endswith("/"):
            untracked_dirs.append(path)
        elif line.startswith("?? ") and "/" in path:
            top = path.split("/", 1)[0] + "/"
            if top not in untracked_dirs:
                untracked_dirs.append(top)
        elif line:
            dirty_files.append(path)
    states.append({
        "repo": name,
        "path": str(repo),
        "branch": run(repo, ["branch", "--show-current"]),
        "commit": run(repo, ["rev-parse", "HEAD"]),
        "upstream": run(repo, ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]),
        "statusShort": status.splitlines(),
        "dirty": bool(status),
        "dirtyFiles": dirty_files,
        "untrackedArtifactDirs": sorted([d for d in untracked_dirs if d.startswith("artifacts/") or d == "artifacts/"]),
        "packagePins": package_pins(repo),
    })

payload = {"schemaVersion": 1, "runID": os.environ.get("WAVE0_RUN_ID"), "repos": states}
mlx_out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
pines_out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

run_ios_smoke() {
  if [ "${WAVE0_SKIP_IOS:-0}" = "1" ]; then
    json_event "pines" "scripts/diagnostics/run-ios-turboquant-bench.sh" "skipped" "Skipped by WAVE0_SKIP_IOS=1." "$PINES_ARTIFACTS/ios-skipped.txt" "$(iso_now)" "$(iso_now)"
    printf 'Skipped by WAVE0_SKIP_IOS=1.\n' >"$PINES_ARTIFACTS/ios-skipped.txt"
    return 0
  fi

  local devices_json="$PINES_ARTIFACTS/devices.json"
  if ! xcrun devicectl list devices --json-output "$devices_json" --quiet >/dev/null 2>"$PINES_ARTIFACTS/logs/devicectl-list.log"; then
    json_event "pines" "xcrun devicectl list devices" "failed_environmental" "Unable to list devices." "$PINES_ARTIFACTS/logs/devicectl-list.log" "$(iso_now)" "$(iso_now)"
    return 0
  fi

  local device_count
  device_count="$(python3 - "$devices_json" <<'PY'
import json, sys
payload = json.load(open(sys.argv[1], encoding="utf-8"))
count = 0
for device in payload.get("result", {}).get("devices", []):
    hardware = device.get("hardwareProperties", {})
    connection = device.get("connectionProperties", {})
    if hardware.get("platform") == "iOS" and hardware.get("reality") == "physical" and connection.get("pairingState") == "paired":
        count += 1
print(count)
PY
)"
  if [ "$device_count" = "0" ]; then
    json_event "pines" "scripts/diagnostics/run-ios-turboquant-bench.sh" "skipped" "skipped_device_unavailable: no paired physical iOS device found." "$devices_json" "$(iso_now)" "$(iso_now)"
    return 0
  fi

  local started finished
  started="$(iso_now)"
  log "Running Pines app-hosted iOS TurboQuant smoke."
  set +e
  (
    cd "$PINES_ROOT"
    PINES_TQ_BENCH_ARTIFACTS="$PINES_ARTIFACTS/ios-smoke" \
    PINES_TQ_BENCH_CONTEXTS=8192 \
    PINES_TQ_BENCH_SCHEMES=turbo4v2 \
    PINES_TQ_BENCH_ITERATIONS=3 \
    PINES_TQ_BENCH_WARMUP=1 \
    PINES_TQ_BENCH_BUILD_TIMEOUT_SECONDS="${WAVE0_IOS_BUILD_TIMEOUT_SECONDS:-300}" \
    bash scripts/diagnostics/run-ios-turboquant-bench.sh
  ) >"$PINES_ARTIFACTS/logs/ios-smoke.log" 2>&1
  local exit_code=$?
  set -e
  finished="$(iso_now)"
  if [ "$exit_code" -eq 0 ]; then
    json_event "pines" "PINES_TQ_BENCH_CONTEXTS=8192 PINES_TQ_BENCH_SCHEMES=turbo4v2 PINES_TQ_BENCH_ITERATIONS=3 PINES_TQ_BENCH_WARMUP=1 bash scripts/diagnostics/run-ios-turboquant-bench.sh" "passed" "App-hosted physical-device smoke completed." "$PINES_ARTIFACTS/ios-smoke/summary.json" "$started" "$finished"
  else
    json_event "pines" "PINES_TQ_BENCH_CONTEXTS=8192 PINES_TQ_BENCH_SCHEMES=turbo4v2 PINES_TQ_BENCH_ITERATIONS=3 PINES_TQ_BENCH_WARMUP=1 bash scripts/diagnostics/run-ios-turboquant-bench.sh" "failed_environmental" "iOS smoke exited with status $exit_code." "$PINES_ARTIFACTS/logs/ios-smoke.log" "$started" "$finished"
  fi
}

summarize_wave0() {
  python3 - "$RUN_ID" "$MLX_ARTIFACTS" "$PINES_ARTIFACTS" <<'PY'
import csv
import json
import pathlib
import sys
from datetime import datetime, timezone

run_id, mlx_artifacts, pines_artifacts = sys.argv[1:]
mlx_artifacts = pathlib.Path(mlx_artifacts)
pines_artifacts = pathlib.Path(pines_artifacts)

repo_state = json.loads((mlx_artifacts / "repo-state.json").read_text(encoding="utf-8"))
events = []
events_path = mlx_artifacts / "validation-events.jsonl"
if events_path.exists():
    for line in events_path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            events.append(json.loads(line))

benchmark_rows = []
for path in sorted((mlx_artifacts / "benchmarks").glob("*/*.json")):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        metrics = data.get("metrics", {})
        path_decision = data.get("pathDecision") or {}
        benchmark_rows.append({
            "mode": path.parent.name,
            "artifactPath": str(path),
            "contextTokens": metrics.get("contextTokens"),
            "preset": metrics.get("preset"),
            "route": metrics.get("route"),
            "backend": metrics.get("backend"),
            "selectedPath": path_decision.get("selectedPath"),
            "decodeTokensPerSecondP50": metrics.get("decodeTokensPerSecondP50"),
            "decodeTokensPerSecondP95": metrics.get("decodeTokensPerSecondP95"),
            "plainDecodeTokensPerSecondP50": metrics.get("plainDecodeTokensPerSecondP50"),
            "plainDecodeTokensPerSecondP95": metrics.get("plainDecodeTokensPerSecondP95"),
            "speedRatioToPlainP50": metrics.get("speedRatioToPlainP50"),
            "speedRatioToPlainP95": metrics.get("speedRatioToPlainP95"),
            "memoryReductionRatio": metrics.get("memoryReductionRatio"),
            "actualBitsPerValue": metrics.get("actualBitsPerValue"),
            "fallbackUsed": metrics.get("fallbackUsed"),
            "fallbackReason": metrics.get("fallbackReason"),
            "tqCoopEnabled": (metrics.get("kernelFlags") or {}).get("tqCoopEnabled"),
        })
    except Exception as exc:
        benchmark_rows.append({"artifactPath": str(path), "error": str(exc)})

ios_summary = None
ios_result = None
for candidate in [
    pines_artifacts / "ios-smoke/summary.json",
    pines_artifacts / "summary.json",
]:
    if candidate.exists():
        ios_summary = json.loads(candidate.read_text(encoding="utf-8"))
        result_file = ios_summary.get("resultFile")
        if result_file and pathlib.Path(result_file).exists():
            ios_result = json.loads(pathlib.Path(result_file).read_text(encoding="utf-8"))
        break

ios_speed_ratio = None
if ios_result and ios_result.get("results"):
    ratios = [r.get("speedRatioToPlain", 0) for r in ios_result["results"] if r.get("status") == "ok"]
    if ratios:
        ios_speed_ratio = min(ratios)

failed_events = [e for e in events if e.get("result") in {"failed", "failed_environmental"}]
ios_passed = any(e.get("repo") == "pines" and "run-ios-turboquant-bench" in e.get("command", "") and e.get("result") == "passed" for e in events)
all_local_passed = not any(e.get("result") == "failed" for e in events if "run-ios-turboquant-bench" not in e.get("command", ""))
performance_parity = bool(ios_speed_ratio is not None and ios_speed_ratio >= 0.9)
stability_parity = "complete" if all_local_passed and ios_passed else "partial"

summary = {
    "schemaVersion": 1,
    "createdAt": datetime.now(timezone.utc).isoformat(),
    "runID": run_id,
    "repoState": repo_state,
    "validationCommands": events,
    "benchmarks": benchmark_rows,
    "iosSummary": ios_summary,
    "iosResult": ios_result,
    "parityVerdict": {
        "performanceParity": performance_parity,
        "performanceParityReason": (
            f"minimum iOS compressed/plain speed ratio {ios_speed_ratio:.4f}" if ios_speed_ratio is not None
            else "no completed iOS compressed/plain benchmark result"
        ),
        "stabilityParity": stability_parity,
        "supportParity": "partial",
    },
    "nextWaveBlockers": [
        "compressed equal-context throughput remains below raw FP16 unless performanceParity is true",
        "native MLX backend operator is not implemented in Wave 0",
        "Verified/Certified product claims require exact real-device evidence tuples",
    ],
}

for target in [mlx_artifacts / "wave0-summary.json", pines_artifacts / "wave0-summary.json"]:
    target.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")

csv_path = mlx_artifacts / "wave0-benchmarks.csv"
with csv_path.open("w", newline="", encoding="utf-8") as handle:
    fieldnames = [
        "mode", "contextTokens", "preset", "route", "backend", "selectedPath",
        "decodeTokensPerSecondP50", "decodeTokensPerSecondP95",
        "plainDecodeTokensPerSecondP50", "plainDecodeTokensPerSecondP95",
        "speedRatioToPlainP50", "speedRatioToPlainP95", "memoryReductionRatio",
        "actualBitsPerValue", "fallbackUsed", "tqCoopEnabled", "artifactPath",
    ]
    writer = csv.DictWriter(handle, fieldnames=fieldnames)
    writer.writeheader()
    for row in benchmark_rows:
        writer.writerow({key: row.get(key) for key in fieldnames})

lines = [
    "# TurboQuant Wave 0 Summary",
    "",
    f"- Run ID: `{run_id}`",
    f"- Created: `{summary['createdAt']}`",
    f"- MLX artifacts: `{mlx_artifacts}`",
    f"- Pines artifacts: `{pines_artifacts}`",
    f"- Performance parity: `{str(performance_parity).lower()}`",
    f"- Stability parity: `{stability_parity}`",
    f"- Support parity: `partial`",
    "",
    "## Repos",
]
for repo in repo_state.get("repos", []):
    lines.append(f"- `{repo['repo']}` `{repo.get('branch')}` `{repo.get('commit')}` dirty=`{repo.get('dirty')}`")
lines.extend(["", "## Validation"])
for event in events:
    lines.append(f"- `{event.get('result')}` `{event.get('repo')}` `{event.get('command')}` -> `{event.get('artifactPath')}`")
lines.extend(["", "## Benchmarks"])
for row in benchmark_rows:
    if "error" in row:
        lines.append(f"- parse error `{row['artifactPath']}`: {row['error']}")
    else:
        lines.append(
            f"- `{row.get('mode')}` `{row.get('preset')}` ctx=`{row.get('contextTokens')}` "
            f"route=`{row.get('route')}` backend=`{row.get('backend')}` "
            f"compressed p50=`{row.get('decodeTokensPerSecondP50')}` "
            f"plain p50=`{row.get('plainDecodeTokensPerSecondP50')}` "
            f"ratio=`{row.get('speedRatioToPlainP50')}` "
            f"coop=`{row.get('tqCoopEnabled')}`"
        )
if ios_summary:
    lines.extend(["", "## iOS Smoke", f"- result: `{ios_summary.get('result')}` reason: `{ios_summary.get('reason')}`"])
    if ios_speed_ratio is not None:
        lines.append(f"- minimum speed ratio: `{ios_speed_ratio:.6f}`")
else:
    ios_events = [e for e in events if "run-ios-turboquant-bench" in e.get("command", "")]
    if ios_events:
        event = ios_events[-1]
        lines.extend([
            "",
            "## iOS Smoke",
            f"- result: `{event.get('result')}` reason: `{event.get('notes')}`",
        ])
    else:
        lines.extend(["", "## iOS Smoke", "- no iOS smoke summary was produced"])
lines.extend(["", "## Gaps", *[f"- {item}" for item in summary["nextWaveBlockers"]], ""])

for target in [mlx_artifacts / "wave0-summary.md", pines_artifacts / "wave0-summary.md"]:
    target.write_text("\n".join(lines), encoding="utf-8")
PY
}

export WAVE0_RUN_ID="$RUN_ID"
log "Capturing repo state."
record_repo_state

run_logged "mlx-swift" "$MLX_FORKS_ROOT/mlx-swift" "build-turboquantbenchmark" "swift build --product TurboQuantBenchmark -c release"

contexts_csv="${WAVE0_CONTEXTS:-8192,16384,32768,65536,131072}"
presets_csv="${WAVE0_PRESETS:-turbo8,turbo4v2,turbo3_5}"
IFS=',' read -r -a contexts <<< "$contexts_csv"
IFS=',' read -r -a presets <<< "$presets_csv"
for preset in "${presets[@]}"; do
  for context in "${contexts[@]}"; do
    run_json_benchmark "default" "$preset" "$context" ""
    run_json_benchmark "coop" "$preset" "$context" "TQ_COOP=1 "
  done
done

run_logged "mlx-swift" "$MLX_FORKS_ROOT/mlx-swift" "test-turboquant" "swift test --filter TurboQuant"
run_logged "mlx-swift-lm" "$MLX_FORKS_ROOT/mlx-swift-lm" "test-turboquant" "swift test --filter TurboQuant"
run_logged "mlx-swift-lm" "$MLX_FORKS_ROOT/mlx-swift-lm" "build-turboquantbench" "swift build --product TurboQuantBench -c release"
run_logged "mlx-swift-lm" "$MLX_FORKS_ROOT/mlx-swift-lm" "test-turboquantbench" "swift test --filter TurboQuantBench"
run_logged "pines" "$PINES_ROOT" "pin-drift" "swift test --filter TurboQuantPinDriftTests"
run_logged "pines" "$PINES_ROOT" "check-mlx-package-pins" "bash scripts/ci/check-mlx-package-pins.sh"

if [ "${WAVE0_SKIP_XCODE_BUILD:-0}" = "1" ]; then
  json_event "pines" "xcodebuild generic iOS build" "skipped" "Skipped by WAVE0_SKIP_XCODE_BUILD=1." "$PINES_ARTIFACTS/logs/xcodebuild-generic-ios.log" "$(iso_now)" "$(iso_now)"
else
  run_logged "pines" "$PINES_ROOT" "xcodebuild-generic-ios" "xcodebuild -project Pines.xcodeproj -scheme Pines -destination 'generic/platform=iOS' -skipMacroValidation -skipPackagePluginValidation -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution -scmProvider system CODE_SIGNING_ALLOWED=NO build"
fi

run_ios_smoke
summarize_wave0

log "Wave 0 capture complete."
log "MLX artifacts: $MLX_ARTIFACTS"
log "Pines artifacts: $PINES_ARTIFACTS"
