# Runtime Bridge Integration

INT-1 is the integration point where the Pines control plane begins driving local MLX generation. This is intentionally a late integration branch so DTOs, failure mapping, admission, and run ledger can be implemented independently first.

In the executable launch schedule, INT-1 is Wave 2 and is serialized. Do not start it until Wave 0 safety/contracts and Wave 1 admission/RunDecision building blocks are usable. Do not run competing edits against the main runtime bridge while INT-1 is active.

## Owned files

INT-1 owns:

- `Pines/Runtime/MLXRuntimeBridge.swift`
- `Pines/Runtime/MLXRuntimeBridge+Admission.swift`
- `Pines/Runtime/MLXRuntimeBridge+TurboQuantDiagnostics.swift`

No other worker should make central generation-loop changes.

## Prerequisites

Before INT-1:

1. W4: LM product path cannot return zeros and cannot fatal.
2. W1: MLX core contracts exist or Pines shim fallback exists.
3. W7: Pines local DTO shims exist.
4. W24: mode/fallback contract exists.
5. W8: admission service exists.
6. W9: RunDecision exists.
7. W21: failure matrix exists.

## Integration flow

```text
chat request
  -> route policy
  -> context assembly v1
  -> device/memory probe
  -> evidence lookup
  -> mode/fallback contract
  -> admission
  -> reject/downgrade or create MLX cache
  -> exact prefill
  -> compressed commit
  -> compressed-domain decode
  -> budgeted fallback only if allowed
  -> cache snapshot query
  -> run decision metadata
  -> memory calibration sample
  -> finish or typed failure
```

## Required behavior

1. Call `LocalRuntimeAdmissionService` before generation.
2. Use `admittedContextTokens`, not requested tokens.
3. Build or retrieve minimal `ContextAssemblyPlan.v1`.
4. Create cache with fallback policy derived from admission.
5. Map MLX/LM typed errors to Pines typed stream failures.
6. Query LM cache runtime snapshot after prefill and decode when available.
7. Attach `TurboQuantRunDecision` to `InferenceFinish.providerMetadata`.
8. Attach partial RunDecision to failures when possible.
9. Attach memory calibration sample.
10. Never cloud retry unless route policy explicitly permits.

## Error mapping

Map lower-level failures to:

- `memoryAdmissionFailed`;
- `turboQuantPathUnavailable`;
- `turboQuantFallbackUnavailable`;
- `fallbackBudgetExceeded`;
- `modelProfileUnverified`;
- `modelProfileMismatch`;
- `unsupportedAttentionShape`;
- `unsupportedAttentionMask`;
- `unsupportedTensorDType`;
- `cacheLayoutInvalid`;
- `cacheLifecycleInvalid`;
- `contextWindowExceeded`;
- `snapshotInvalid`;
- `mlxRuntimeFailure`;
- `cloudRouteDisallowed`.

Rules:

- Preserve original error string in support metadata.
- Do not expose low-level kernel details in normal UI.
- Technical details may show selected and rejected paths.

## Metadata requirements

Finish metadata includes:

- compatibility pair ID;
- admission plan;
- context assembly plan ID or inline v1 summary;
- selected attention path;
- rejected paths;
- fallback contract hash;
- fallback used/reason;
- compressed KV bytes;
- raw shadow allocation;
- packed fallback allocation;
- cache lifecycle;
- input/output token counts;
- memory calibration sample ID;
- evidence ID if used.

Failure metadata includes:

- failure event;
- admission if available;
- partial RunDecision if available;
- route decision;
- user-safe recommended action.

## Cloud boundary

Local failure never silently becomes cloud execution.

Allowed cloud retry path:

1. route policy permits cloud;
2. user or stored policy explicitly allows retry;
3. local failure is recorded;
4. cloud route decision is recorded;
5. local vault or memory content inclusion obeys privacy approvals.

## Minimal ContextAssemblyPlan in MVP 1

INT-1 should not wait for full MVP 2 context virtualization. It should attach v1 metadata using current behavior:

- pinned prompt/system instructions;
- included recent messages;
- clipped messages;
- exact token count;
- truncation reason.

MVP 2 later expands this into retrieved vault chunks, summaries, dropped segments, and exact-prefix KV page references.

## Tests

Required:

- unsafe run rejected before generation;
- admitted context used in prompt/token preflight;
- typed MLX failure reaches stream failure;
- cloud disallowed prevents fallback route;
- successful local run emits RunDecision;
- failure local run emits partial RunDecision;
- fallback budget exceeded maps to typed failure;
- metadata JSON is stable.
