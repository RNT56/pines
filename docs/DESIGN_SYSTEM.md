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
- `Sunset`: copper-orange workspace with warm glass.
- `Obsidian`: dark-first pro console with restrained luminous accents.

## Interface Modes

Each template supports:

- `System`
- `Light`
- `Dark`

The selected mode is applied through `preferredColorScheme`, while the resolved theme is injected through the SwiftUI environment.

## Theme Depth

Each template defines a full light and dark schema for:

- app, content, sidebar, sheet, card, list, chrome, control, code, quote, table, and modal surfaces
- primary, secondary, tertiary, placeholder, disabled, separator, link, and focus roles
- success, warning, danger, info, soft semantic fills, chat bubbles, selection, hover, and pressed states
- six chart/accent swatches used by previews and analytics surfaces
- material choice, background wash, and surface highlight behavior

Graphite intentionally stays closest to the original dense neutral system. The other themes carry stronger identity in both light and dark modes:

| Theme | Light mode | Dark mode |
| --- | --- | --- |
| Evergreen | botanical sage, ivory surfaces, pine ink | deep forest glass, mint highlights, moss/gold support |
| Aurora | blue-lilac research surfaces, violet/cyan charts | night-sky navy, cyan/violet glow, saturated data colors |
| Paper | parchment, book ink, muted green and ochre | archival charcoal paper, warm text, olive and brass accents |
| Slate | steel-blue operational UI, crisp cool surfaces | instrument-panel blue-gray, cyan edge light |
| Porcelain | ceramic whites, mauve/cobalt editorial accents | glazed plum-black, rose porcelain highlights |
| Sunset | copper, clay, and warm paper surfaces | ember-black console, copper and rose heat |
| Obsidian | smoke-glass light mode with teal contrast | near-black console with restrained cyan luminous accents |

## Covered Style Surface

`PinesTheme` controls:

- semantic colors
- content, sidebar, sheet, card, themed grouped-list, chrome, list-row, and disabled-state roles
- typography
- spacing
- radii
- strokes
- shadows
- materials
- motion curves
- semantic soft fills for success, warning, danger, and info states
- expanded chart swatches
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

Sidebar lists should use the shared list chrome so SwiftUI grouped-list containers do not fall back to system light/dark surfaces:

```swift
List {
    Section("Recent") {
        NavigationLink(value: item.id) {
            PinesSidebarRow(...)
        }
        .pinesSidebarListRow()
    }
}
.pinesSidebarListChrome()
```

## Rules

- Do not introduce feature-local color palettes.
- Do not hard-code light/dark colors in views.
- Keep cards at 8 pt radius unless the theme radius changes.
- Use semantic colors for states: success, warning, danger, info, accent.
- Respect Reduce Motion when adding custom animation.
- Keep dense operational screens scannable; avoid marketing-style hero layouts.
