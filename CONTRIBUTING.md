# Contributing

This project is early and intentionally modular. Keep changes aligned with the existing boundaries.

## Development

```sh
xcodegen generate
swift build --disable-automatic-resolution
swift test --disable-automatic-resolution
swift run --disable-automatic-resolution PinesCoreTestRunner
```

Use XcodeGen `2.45.4` or newer and full Xcode for iOS builds.

## Guidelines

- Keep app UI in `Pines/`.
- Keep testable domain/runtime contracts in `Sources/PinesCore/`.
- Do not make SwiftUI views construct persistence, cloud, or inference services directly.
- Add new feature ownership to `PinesArchitecture.modules`.
- Add new theme values to `PinesDesignSystem.swift` and reusable UI primitives to `PinesDesignComponents.swift` instead of creating view-local styling.
- Keep large app files split by feature concern. Prefer companion files such as `+CloudKit`, `Payloads`, `Support`, `Types`, `Components`, or model-family files when a file starts mixing unrelated responsibilities.
- Keep the MLX fork pins in `project.yml` and `Pines.xcodeproj` aligned. Do not point the app at upstream MLX package releases until the required TurboQuant APIs are available there.
- Do not commit secrets, local environment files, DerivedData, or `.build`.

## Licensing

By submitting a contribution, you confirm that you have the right to provide it and that it is licensed under the repository license: PolyForm Noncommercial License 1.0.0 (`PolyForm-Noncommercial-1.0.0`). Do not submit code, assets, or documentation that cannot be distributed under that license.
