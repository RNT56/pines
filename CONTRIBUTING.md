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
