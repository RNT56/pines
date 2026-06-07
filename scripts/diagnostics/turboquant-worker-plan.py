#!/usr/bin/env python3
"""Inspect and validate the TurboQuant multi-worker execution manifest."""

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = (
    ROOT / "docs/turboquant-implementation/18-multi-worker-execution-manifest.json"
)
DEFAULT_COMPATIBILITY = ROOT / "docs/turboquant-implementation/compatibility-pair.json"


def load_json(path: pathlib.Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return payload


def repo_status(path: pathlib.Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(path), "status", "--short", "--branch"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return "git status unavailable"


def workers_by_id(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    workers = manifest.get("workers", [])
    if not isinstance(workers, list):
        raise ValueError("manifest workers must be an array")
    result: dict[str, dict[str, Any]] = {}
    for worker in workers:
        if not isinstance(worker, dict):
            raise ValueError("each worker must be an object")
        worker_id = worker.get("id")
        if not isinstance(worker_id, str) or not worker_id:
            raise ValueError("each worker must have a non-empty string id")
        if worker_id in result:
            raise ValueError(f"duplicate worker id: {worker_id}")
        result[worker_id] = worker
    return result


def waves_by_id(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    waves = manifest.get("waves", [])
    if not isinstance(waves, list):
        raise ValueError("manifest waves must be an array")
    result: dict[str, dict[str, Any]] = {}
    for wave in waves:
        if not isinstance(wave, dict):
            raise ValueError("each wave must be an object")
        wave_id = wave.get("id")
        if not isinstance(wave_id, str) or not wave_id:
            raise ValueError("each wave must have a non-empty string id")
        if wave_id in result:
            raise ValueError(f"duplicate wave id: {wave_id}")
        result[wave_id] = wave
    return result


def validate_manifest(manifest: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    policy = manifest.get("promotionPolicy", {})
    if not isinstance(policy, dict):
        errors.append("promotionPolicy must be an object")
        policy = {}
    if policy.get("bar") != "verifiedOnly":
        errors.append("promotionPolicy.bar must be verifiedOnly")
    if policy.get("productionCompressedBaseline") != "affineK8V4":
        errors.append("productionCompressedBaseline must be affineK8V4")
    if policy.get("historicalSyntheticSimulatorOrDenseFallbackEvidenceMayPromote") is not False:
        errors.append("historical/synthetic/simulator/dense-fallback promotion must be false")

    defaults = policy.get("defaultActivation", {})
    if not isinstance(defaults, dict):
        errors.append("promotionPolicy.defaultActivation must be an object")
        defaults = {}
    for path in policy.get("experimentalPaths", []):
        if path == "affineK8V4":
            continue
        if defaults.get(path) != "disabledUntilVerified":
            errors.append(f"{path} must default to disabledUntilVerified")

    try:
        workers = workers_by_id(manifest)
        waves = waves_by_id(manifest)
    except ValueError as exc:
        return errors + [str(exc)]

    gates = manifest.get("gates", {})
    if not isinstance(gates, dict):
        errors.append("gates must be an object")
        gates = {}

    for wave_id, wave in waves.items():
        wave_workers = wave.get("workers", [])
        if not isinstance(wave_workers, list):
            errors.append(f"{wave_id} workers must be an array")
            continue
        for worker_id in wave_workers:
            if worker_id not in workers:
                errors.append(f"{wave_id} references unknown worker {worker_id}")
        for dependency in wave.get("dependsOn", []):
            if dependency not in waves:
                errors.append(f"{wave_id} depends on unknown wave {dependency}")

    for worker_id, worker in workers.items():
        wave_id = worker.get("wave")
        if wave_id not in waves:
            errors.append(f"{worker_id} references unknown wave {wave_id}")
        elif worker_id not in waves[wave_id].get("workers", []):
            errors.append(f"{worker_id} is not listed in {wave_id}.workers")
        for dependency in worker.get("dependsOn", []):
            if dependency not in workers:
                errors.append(f"{worker_id} depends on unknown worker {dependency}")
        for gate in worker.get("requiredGates", []):
            if gate not in gates:
                errors.append(f"{worker_id} references unknown gate {gate}")

    serialized = manifest.get("serializedOwnership", [])
    if not isinstance(serialized, list):
        errors.append("serializedOwnership must be an array")
    else:
        for entry in serialized:
            if not isinstance(entry, dict):
                errors.append("serializedOwnership entries must be objects")
                continue
            owners = entry.get("owners", [])
            for owner in owners:
                if owner not in workers:
                    errors.append(f"serialized owner {owner} is not a known worker")

    return errors


def validate_compatibility(
    manifest: dict[str, Any],
    compatibility_path: pathlib.Path,
) -> list[str]:
    errors: list[str] = []
    compatibility = load_json(compatibility_path)
    status = compatibility.get("status")
    readiness = compatibility.get("releaseReadiness", {})
    claim_policy = compatibility.get("claimPolicy", {})
    green_allowed = readiness.get("greenAllowed") if isinstance(readiness, dict) else None
    verified_claims = (
        claim_policy.get("verifiedOrCertifiedProductClaimsAllowed")
        if isinstance(claim_policy, dict)
        else None
    )

    if status == "green" and green_allowed is not True:
        errors.append("compatibility-pair status is green while releaseReadiness.greenAllowed is not true")

    if manifest.get("promotionPolicy", {}).get("bar") == "verifiedOnly":
        if verified_claims and green_allowed is not True:
            errors.append("Verified/Certified claims are allowed before greenAllowed is true")

    required = set()
    if isinstance(readiness, dict):
        required = set(readiness.get("requiredEvidenceForGreen", []))
    expected = {
        "native_backend_performance",
        "performance_parity",
        "real_model_inference",
        "real_device_app_host",
        "benchmark_matrix",
        "quality_memory_fallback",
    }
    missing = expected.difference(required)
    if missing:
        errors.append(
            "releaseReadiness.requiredEvidenceForGreen is missing: "
            + ", ".join(sorted(missing))
        )

    return errors


def worker_lines(
    worker: dict[str, Any],
    manifest: dict[str, Any],
    include_status: bool = False,
) -> list[str]:
    repo_roots = manifest.get("repoRoots", {})
    repo = str(worker.get("repo", ""))
    first_repo = repo.split(",", 1)[0]
    root = repo_roots.get(first_repo)
    lines = [
        f"## {worker['id']} - {worker.get('task', '')}",
        f"Wave: {worker.get('wave')}",
        f"Repo: {repo}",
        f"Branch: {worker.get('branch')}",
        f"Target: {worker.get('targetBranch')}",
        f"Activation: {worker.get('activationStatus')}",
    ]
    dependencies = worker.get("dependsOn", [])
    if dependencies:
        lines.append("Depends on: " + ", ".join(dependencies))
    owns = worker.get("owns", [])
    if owns:
        lines.append("Owns: " + "; ".join(owns))
    must_not_touch = worker.get("mustNotTouch", [])
    if must_not_touch:
        lines.append("Do not touch: " + "; ".join(must_not_touch))
    gates = worker.get("requiredGates", [])
    if gates:
        lines.append("Required gates: " + ", ".join(gates))
    if root:
        lines.append(f"Start command: cd {root} && git status --short --branch")
        if include_status:
            lines.append("Current status:")
            status = repo_status(pathlib.Path(root))
            lines.extend(f"  {line}" for line in status.splitlines() or ["clean"])
    lines.append("")
    lines.append("Required output:")
    lines.extend(
        [
            "Scope:",
            "Wave:",
            "Owned files:",
            "Files intentionally not touched:",
            "Contracts used:",
            "Schemas changed:",
            "Feature flags:",
            "Tests added:",
            "Manual validation:",
            "Evidence artifacts:",
            "Known follow-up:",
            "Activation status:",
            "Compatibility-pair impact:",
        ]
    )
    return lines


def print_workers(
    manifest: dict[str, Any],
    worker_filter: str | None,
    wave_filter: str | None,
    include_status: bool,
) -> int:
    workers = workers_by_id(manifest)
    waves = waves_by_id(manifest)

    selected: list[dict[str, Any]] = []
    if worker_filter:
        worker = workers.get(worker_filter)
        if worker is None:
            print(f"unknown worker: {worker_filter}", file=sys.stderr)
            return 2
        selected = [worker]
    elif wave_filter:
        wave = waves.get(wave_filter)
        if wave is None:
            print(f"unknown wave: {wave_filter}", file=sys.stderr)
            return 2
        selected = [workers[worker_id] for worker_id in wave.get("workers", [])]
    else:
        for wave in manifest.get("waves", []):
            selected.extend(workers[worker_id] for worker_id in wave.get("workers", []))

    for index, worker in enumerate(selected):
        if index:
            print()
        print("\n".join(worker_lines(worker, manifest, include_status)))
    return 0


def print_matrix(manifest: dict[str, Any]) -> None:
    workers = workers_by_id(manifest)
    for wave in manifest.get("waves", []):
        worker_ids = wave.get("workers", [])
        print(f"{wave['id']}: {wave.get('name', '')}")
        print("  parallel:", str(wave.get("parallel", False)).lower())
        print("  workers:", ", ".join(worker_ids))
        blockers = []
        for worker_id in worker_ids:
            worker = workers[worker_id]
            dependencies = worker.get("dependsOn", [])
            if dependencies:
                blockers.append(f"{worker_id} waits for {', '.join(dependencies)}")
        if blockers:
            print("  dependencies:")
            for blocker in blockers:
                print("    -", blocker)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=pathlib.Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--compatibility-path", type=pathlib.Path, default=DEFAULT_COMPATIBILITY)
    parser.add_argument("--validate", action="store_true", help="validate manifest invariants")
    parser.add_argument("--compatibility", action="store_true", help="validate compatibility-pair policy")
    parser.add_argument("--list", action="store_true", help="list worker cards")
    parser.add_argument("--worker", help="print a single worker card")
    parser.add_argument("--wave", help="print worker cards for one wave")
    parser.add_argument("--matrix", action="store_true", help="print wave dependency matrix")
    parser.add_argument("--status", action="store_true", help="include git status in worker cards")
    args = parser.parse_args()

    try:
        manifest = load_json(args.manifest)
        errors: list[str] = []
        if args.validate or not (args.list or args.worker or args.wave or args.matrix):
            errors.extend(validate_manifest(manifest))
        if args.compatibility:
            errors.extend(validate_compatibility(manifest, args.compatibility_path))
        if errors:
            for error in errors:
                print(f"error: {error}", file=sys.stderr)
            return 1
        if args.validate or args.compatibility:
            print("TurboQuant worker manifest checks passed.")
        if args.matrix:
            print_matrix(manifest)
        if args.list or args.worker or args.wave:
            return print_workers(manifest, args.worker, args.wave, args.status)
        return 0
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
