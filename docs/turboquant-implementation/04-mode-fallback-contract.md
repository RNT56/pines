# Mode and Fallback Contract

User modes are product-level contracts, not just presets. Each mode defines context target, fallback reserve, performance goal, and what Pines may do when the preferred compressed path is unavailable.

Launch wave: Wave 0. W24 defines this contract before W8 admission and INT-1 bridge integration consume it.

## User modes

| Mode | Goal | Context | Fallback | Notes |
| --- | --- | --- | --- | --- |
| `fastest` | speed | short | limited | prioritize low latency and high-confidence paths |
| `balanced` | default | medium | full budgeted | quality-first production default |
| `maxContext` | largest safe context | long | minimal | user-selected tradeoff; requires evidence for large claims |
| `batterySaver` | energy | short | limited | conservative under Low Power Mode or thermal pressure |

## Correct downgrade order

Max Context is not a downgrade from Balanced. It is a user-selected tradeoff with lower fallback reserve.

Downgrade order:

```text
Max Context -> Max Context shorter -> Balanced shorter -> Battery Saver shorter -> typed failure
Balanced -> Balanced shorter -> Battery Saver shorter -> typed failure
Fastest -> Fastest shorter -> Battery Saver shorter -> typed failure
Battery Saver -> Battery Saver shorter -> typed failure
```

Rules:

- Balanced never downgrades to Max Context.
- A downgrade must preserve or reduce memory risk.
- A downgrade must record `downgradeReason`.
- A shorter-context retry must be allowed by the fallback contract.
- Cloud retry is never part of mode downgrade. It is controlled only by route policy.

## Fallback contract type

```swift
public struct TurboQuantFallbackContract: Codable, Sendable {
    public var allowPackedFallback: Bool
    public var allowDecodedLayerLocalFallback: Bool
    public var allowFullDecodedFallback: Bool
    public var allowShorterContextRetry: Bool
    public var allowCloudRetry: Bool
    public var failIfCompressedPathUnavailable: Bool
    public var reserveBytes: Int64
}
```

## Default fallback policy by mode

| Mode | Packed fallback | Layer-local decoded fallback | Full decoded fallback | Shorter retry | Cloud retry |
| --- | --- | --- | --- | --- | --- |
| Fastest | yes | no | no | yes | explicit policy only |
| Balanced | yes | yes | no | yes | explicit policy only |
| Max Context | optional | no | no | yes | explicit policy only |
| Battery Saver | optional | no | no | yes | explicit policy only |

Full decoded fallback is disabled by default in product modes because it can duplicate the long-context cache and invalidate admission. If a debug or benchmark mode enables full decoded fallback, admission must reserve it explicitly and RunDecision must record it.

## Mode-to-admission rules

### Fastest

Purpose:

- short local responses;
- lower first-token latency;
- high confidence in selected path;
- avoid expensive warmup and fallback allocations.

Admission:

- smaller context target;
- packed fallback allowed;
- decoded fallback disabled;
- kernel warmup optional;
- evidence preferred but conservative mode may run without verified evidence.

### Balanced

Purpose:

- default user-facing local mode;
- highest correctness margin;
- normal fallback reserve.

Admission:

- medium context target;
- packed fallback allowed;
- layer-local decoded fallback allowed if budgeted;
- full decoded fallback disabled;
- evidence used for verified claim;
- missing evidence results in conservative admitted context.

### Max Context

Purpose:

- largest safe context with explicit tradeoffs.

Admission:

- long context target;
- minimal fallback reserve;
- packed fallback optional by evidence and memory;
- decoded fallback disabled;
- large product claims require verified or certified evidence;
- if compressed path is unavailable and `failIfCompressedPathUnavailable` is true, reject rather than silently fall back to a huge decoded cache.

### Battery Saver

Purpose:

- reduce energy and thermal risk.

Admission:

- short context target;
- minimal fallback reserve;
- no decoded fallback;
- reduced kernel warmup;
- thermal and Low Power Mode compatible.

## Fallback contract hash

Every evidence record must include a fallback contract hash.

Hash inputs:

- mode;
- packed fallback flag;
- layer-local decoded fallback flag;
- full decoded fallback flag;
- shorter retry flag;
- cloud retry flag;
- compressed path required flag;
- reserve bytes class or exact reserve;
- schema version.

Evidence is invalid if fallback contract hash changes.

## UI requirements

Mode UI must show:

- admitted context per mode;
- whether mode is verified, conservative, unsupported, degraded, or benchmark-required;
- fallback policy summary;
- user-facing reason for reduction or rejection.

Technical details must show:

- selected attention path;
- fallback reserve bytes;
- fallback used;
- fallback reason;
- evidence ID and date if applicable.

## Tests

Required tests:

- Balanced never downgrades to Max Context.
- Max Context shorter can downgrade to Balanced shorter.
- Cloud retry remains false unless route policy allows it.
- Full decoded fallback cannot be selected without explicit budget.
- `fallbackContractHash` changes when any fallback flag changes.
- User-facing copy exists for rejection and downgrade.
