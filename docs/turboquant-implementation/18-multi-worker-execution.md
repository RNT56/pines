# Multi-Worker Execution

This document turns the worker launch schedule into an executable coordination
surface. The machine-readable source of truth is
[18-multi-worker-execution-manifest.json](18-multi-worker-execution-manifest.json).

Use it when launching parallel agents, preparing worker PR descriptions, or
checking that a release-green decision still respects the Verified Only bar.

## Operator Commands

Validate the manifest and the current compatibility-pair policy:

```bash
python3 scripts/diagnostics/turboquant-worker-plan.py --validate --compatibility
```

List all workers in wave order:

```bash
python3 scripts/diagnostics/turboquant-worker-plan.py --list
```

Print only runnable worker cards for a wave:

```bash
python3 scripts/diagnostics/turboquant-worker-plan.py --wave wave-3
```

Print one worker handoff card:

```bash
python3 scripts/diagnostics/turboquant-worker-plan.py --worker W13
```

## Dispatch Rules

- Start each worker with `git status --short --branch` in its assigned repo.
- Treat dirty files as owned by another active worker unless the file is listed
  in that worker's `owns` field.
- Use `targetBranch` from the manifest for PRs and keep worker branches small.
- Do not edit serialized ownership areas unless the worker ID is listed as an
  owner in the manifest.
- Keep `affineK8V4` as the only production compressed baseline until another
  path independently passes the same current real-device evidence bar.
- Keep lower-V, Sparse-V, snapshots, speculative decoding, Layout V5, and
  Wave 7 platform unlocks disabled or debug-only until their exact gates pass.

## Worker Output Contract

Each worker final message or PR body must include:

```text
Scope:
Wave:
Owned files:
Files intentionally not touched:
Contracts used:
Schemas changed:
Feature flags:
Tests added:
Manual validation:
Evidence artifacts:
Known follow-up:
Activation status:
Compatibility-pair impact:
```

## Green-Status Rule

The script intentionally fails if the compatibility pair is marked `green`
without `releaseReadiness.greenAllowed == true`, or if Verified/Certified
product claims are allowed while the manifest is still set to the Verified Only
release bar. Passing the script is not enough to certify a release; it only
guards the coordination rules before the full validation matrix runs.
