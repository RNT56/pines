# Contributing

This project is early and intentionally modular. Keep changes aligned with the existing boundaries.

## Development

```sh
xcodegen generate
swift build
swift run PinesCoreTestRunner
```

Use full Xcode for iOS builds.

## Guidelines

- Keep app UI in `Pines/`.
- Keep testable domain/runtime contracts in `Sources/PinesCore/`.
- Do not make SwiftUI views construct persistence, cloud, or inference services directly.
- Add new feature ownership to `PinesArchitecture.modules`.
- Add new theme values to `PinesDesignSystem.swift` instead of creating view-local styling.
- Do not commit secrets, local environment files, DerivedData, or `.build`.

## Licensing

By submitting a contribution, you confirm that you have the right to provide it and that it is licensed under the repository license: PolyForm Noncommercial License 1.0.0 (`PolyForm-Noncommercial-1.0.0`). Do not submit code, assets, or documentation that cannot be distributed under that license.
