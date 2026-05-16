# Design System

The app uses a single environment-driven design system. `PinesDesignSystem.swift` owns tokens, templates, theme resolution, and environment injection. `PinesDesignComponents.swift` owns reusable SwiftUI surfaces, rows, empty states, cards, panels, pills, haptics modifiers, and convenience view modifiers. Screens should not hard-code palette, spacing, material, or motion choices. They should consume `\.pinesTheme`.

## Theme Templates

The current templates are:

- `Evergreen`: default local-first look with pine green, glass cyan, and calm surfaces.
- `Graphite`: dense professional workspace with neutral contrast.
- `Aurora`: cooler research surface with brighter blue/violet accents.
- `Paper`: warmer reading and vault-focused layout.
- `Slate`: technical blue-gray workspace with quiet precision.
- `Porcelain`: warm ceramic minimalism with fine editorial contrast.
- `Sunset`: Bitcoin-orange workspace with warm copper glass.
- `Obsidian`: dark-first pro console with restrained luminous accents.

## Interface Modes

Each template supports:

- `System`
- `Light`
- `Dark`

The selected mode is applied through `preferredColorScheme`, while the resolved theme is injected through the SwiftUI environment.

## Covered Style Surface

`PinesTheme` controls:

- semantic colors
- content, sidebar, sheet, card, list-row, and disabled-state roles
- typography
- spacing
- radii
- strokes
- shadows
- materials
- motion curves
- semantic soft fills for success, warning, danger, and info states
- panel styling
- empty states
- metric pills
- boot mark
- theme preview cards

This means new screens should be visually complete by default if they use the provided components and environment values.

## File Ownership

- Add palette, typography, spacing, radius, stroke, shadow, material, or motion values in `PinesDesignSystem.swift`.
- Add reusable views and modifiers in `PinesDesignComponents.swift`.
- Keep feature-specific layouts in their feature folders, for example `Views/Models` or `Views/Settings`.
- Avoid rebuilding card, row, pill, and panel styles inside feature views unless the design system is missing a primitive.

## Usage

Read the theme from the environment:

```swift
@Environment(\.pinesTheme) private var theme
```

Use semantic values:

```swift
Text("Models")
    .font(theme.typography.title)
    .foregroundStyle(theme.colors.primaryText)
    .padding(theme.spacing.large)
    .background(theme.colors.surface)
```

Use shared modifiers:

```swift
content
    .pinesPanel()
    .pinesAppBackground()
```

## Rules

- Do not introduce feature-local color palettes.
- Do not hard-code light/dark colors in views.
- Keep cards at 8 pt radius unless the theme radius changes.
- Use semantic colors for states: success, warning, danger, info, accent.
- Respect Reduce Motion when adding custom animation.
- Keep dense operational screens scannable; avoid marketing-style hero layouts.
