# Failure Matrix

Every TurboQuant runtime failure must have deterministic behavior. The system may reject, downgrade, retry shorter, fallback, quarantine, revoke evidence, or emit a typed error. It must not return silent wrong output, fatal in product paths, or silently route to cloud.

## Failure behavior vocabulary

| Behavior | Meaning |
| --- | --- |
| `reject` | stop before generation and emit typed user-safe failure |
| `downgrade` | select a lower-risk local mode or shorter context before generation |
| `retryShorter` | retry locally with smaller admitted context if fallback contract permits |
| `fallback` | use a semantically correct budgeted attention/cache path |
| `cancel` | stop active run cleanly |
| `releaseOptionalCaches` | release prompt cache, vault cache, warm pages, or scratch buffers |
| `quarantine` | mark corrupt/partial snapshot or evidence unusable |
| `revokeEvidence` | move evidence to `Revoked` and prevent verified claims |
| `typedError` | surface structured error to stream/UI/support export |

## Matrix

| Failure | Detection point | Behavior | Owner | Product message |
| --- | --- | --- | --- | --- |
| No Metal | capability probe | reject or downgrade to no-Metal path | Pines | Local accelerated attention is unavailable on this device. |
| TurboQuant codec unavailable | capability probe | downgrade or reject TurboQuant | Pines/MLX | TurboQuant codec is unavailable; using conservative local mode. |
| Fused attention unavailable | path selection | try two-stage if available | MLX | Hidden by default; technical details show path. |
| QK unavailable | path selection | fallback if budgeted, else typed error | MLX/LM | Compressed QK path is unavailable for this shape. |
| AV unavailable | path selection | fallback if budgeted, else typed error | MLX/LM | Compressed AV path is unavailable for this shape. |
| Head dimension unsupported | validation/router | reject path before dispatch | MLX | Model head dimension is unsupported by this TurboQuant path. |
| Mask unsupported | validation/router | fallback if budgeted, else typed error | MLX/LM | Attention mask is unsupported by compressed path. |
| Unsupported dtype | validation/router | fallback or reject path | MLX/LM | Tensor dtype is unsupported by compressed path. |
| Invalid compressed layout | validator | typed error before dispatch | MLX/LM | Compressed cache layout is invalid. |
| Cache logical length invalid | validator | typed error before dispatch | MLX/LM | Cache length is inconsistent. |
| Cache ring offset invalid | validator | typed error before dispatch | MLX/LM | Cache ring state is inconsistent. |
| Decode sees compressing chunk | lifecycle assertion | typed error; no decode | LM | Cache is not committed yet. |
| Low memory before run | admission | downgrade or reject | Pines | This model/context needs more memory than is safely available. |
| Fallback reserve missing | admission | reject or choose no-fallback contract | Pines | Safe fallback cannot be budgeted for this context. |
| Budget exceeded during fallback | fallback ladder | typed error | LM/Pines | Fallback would exceed memory budget. |
| Memory warning during prefill | iOS monitor | cancel or retry shorter if allowed | Pines | Local run stopped to avoid memory termination. |
| Memory warning during decode | iOS monitor | release optional caches, cancel if unsafe | Pines | Local run stopped under memory pressure. |
| Thermal downshift before run | device monitor | downgrade admission | Pines | Device thermal state reduced local context. |
| Thermal downshift during run | device monitor | continue if safe, reduce next admission | Pines | Technical details only unless run stops. |
| Low Power Mode | device monitor | battery policy | Pines | Battery Saver local mode applied. |
| Model/profile mismatch | profile validator | disable TurboQuant | LM/Pines | This model profile does not match the installed model. |
| Model evidence missing | evidence lookup | conservative only | Pines | This model is not verified on this device yet. |
| Evidence regression | benchmark import | revoke evidence | Pines | Previous compatibility evidence was revoked. |
| Tokenizer mismatch | snapshot restore | reject snapshot | Pines | Saved session state is no longer valid for this tokenizer. |
| RoPE mismatch | snapshot restore | reject snapshot | Pines | Saved session state is no longer valid for this model configuration. |
| Profile hash mismatch | snapshot restore | reject snapshot | Pines | Saved session state is no longer valid for this runtime profile. |
| Prefix hash mismatch | snapshot restore | reject snapshot, re-prefill | Pines | Session state cannot be reused because the prompt changed. |
| Partial snapshot write | snapshot open | quarantine | Pines | Saved session state was incomplete and will be rebuilt. |
| Snapshot corruption | snapshot open | quarantine and typed error | Pines | Saved session state is corrupt and cannot be restored. |
| Snapshot schema newer | schema decode | fail closed | Pines | Saved session state was created by a newer incompatible version. |
| Benchmark schema newer | evidence import | fail closed | Pines | Benchmark evidence was created by a newer incompatible version. |
| Hidden long-KV copy detected | benchmark/audit | fail benchmark gate | MLX | Not user-visible; blocks release gate. |
| Cloud disallowed | routing | local typed failure only | Pines | Cloud retry is disabled for this request. |
| Cloud allowed but local failed | routing | require explicit route decision | Pines | Local run failed; cloud retry requires approval or enabled policy. |

## Typed failure enum

Pines maps lower-level errors to:

```swift
public enum LocalInferenceFailureKind: String, Codable, Sendable {
    case memoryAdmissionFailed
    case turboQuantPathUnavailable
    case turboQuantFallbackUnavailable
    case fallbackBudgetExceeded
    case modelProfileUnverified
    case modelProfileMismatch
    case unsupportedAttentionShape
    case unsupportedAttentionMask
    case unsupportedTensorDType
    case cacheLayoutInvalid
    case cacheLifecycleInvalid
    case contextWindowExceeded
    case snapshotInvalid
    case snapshotCorrupt
    case schemaIncompatible
    case mlxRuntimeFailure
    case cloudRouteDisallowed
}
```

## Required tests

P0 tests:

- compressed path forced failure never returns zeros;
- product generation path never calls non-throwing fatal wrapper;
- unsupported head dimension yields typed error or fallback;
- unsupported mask yields typed error or fallback;
- low memory admission rejects before model run;
- cloud disallowed prevents cloud fallback;
- fallback budget exceeded maps to typed failure;
- newer snapshot schema fails closed.

P1 tests:

- codec unavailable downgrades;
- fused unavailable tries two-stage;
- QK unavailable tries budgeted fallback;
- AV unavailable tries budgeted fallback;
- model profile mismatch disables TurboQuant;
- evidence missing produces conservative state;
- memory warning creates failure event or cancels cleanly.

P2 tests:

- partial snapshot write quarantines;
- snapshot identity mismatch rejects restore;
- hidden-copy benchmark gate fails when long-KV copy path is detected;
- evidence regression revokes product claim.

## Support export requirements

Every failure support export includes:

- failure event schema envelope;
- source repo/type;
- original error string;
- mapped failure kind;
- admission plan if available;
- RunDecision if available;
- context assembly plan if available;
- compatibility pair if available;
- evidence ID if involved;
- recommended user action.
