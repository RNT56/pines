# Performance Baseline Ledger

Keep one Markdown record per measured commit and device class, named `YYYY-MM-DD-<device>-<short-sha>.md`. Store large `.trace` and `.xcresult` bundles as CI artifacts or external release evidence; do not commit them.

Use this template:

```md
# Pines performance baseline

- Commit:
- Branch:
- Build configuration: Release / PinesPerformance
- Device and hardware identifier:
- OS build:
- Battery / charging / Low Power Mode:
- Thermal state before and after:
- Dataset fixture and size:
- Network conditions:
- Cold or warm cache protocol:
- Repetitions:

| Journey / metric | p50 | p95 | Peak / hitch count | Goal | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| Launch to interactive | | | | | |
| Thread to first message | | | | | |
| Gallery to first thumbnail | | | | | |
| Artifact library derive | | | | | |
| Vault detail ready | | | | | |
| Provider lifecycle refresh | | | | | |
| Provider transfer peak RSS | | | | | |

## Trace observations

- Main-thread work:
- Longest hitch:
- Memory growth and recovery:
- File/network behavior:
- Poll/query counts:

## Evidence

- `.trace` location:
- `.xcresult` location:
- Build log:
- Release-hygiene result:

## Decision

- Accepted / provisional / rejected:
- Regressions and owners:
```

No device class is accepted until this ledger has a current, reproducible record. Historical traces from a different commit, OS, device, or dependency pin are context only.
