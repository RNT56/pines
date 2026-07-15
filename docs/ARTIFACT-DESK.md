# Artifact Desk UX System

## Product model

Artifacts is a desk, not a nested file browser or a collection of mini-apps. The root remains stable while users browse, inspect, create, and resume work.

The system has four layers:

1. **Command strip** — search, output scope, refinement, and one labeled New action.
2. **Work queue** — a compact horizontal row that appears only while media or research work is active.
3. **Canvas** — one mixed-content collection. Phone uses dense rows; iPad uses a responsive grid.
4. **Focus surface** — artifact details appear in a trailing inspector on iPad and a sheet on phone.

Image, video, audio, and reports are facets of the same collection. They are not pages or tabs. The scope menu filters the canvas without changing the user’s location.

## Creation model

New opens an outcome-first command deck:

- Image
- Video
- Speech
- Research

Choosing an outcome opens one focused composer. Output type is a compact menu, provider/model/options are one setup control, and advanced values remain in a utility sheet. The composer does not contain a second tab bar.

Research uses the same rule. Current and recent research are selected directly from one context menu; history is not another routed page. Source/model setup and optional clarification are utility sheets, while the conversation remains the stable task surface.

## Responsive contract

### iPhone and compact width

- App destinations remain in the system tab bar.
- Artifact results use compact rows so more than one item is visible at a time.
- Details, creation, and research use dismissible sheets over the stable desk.
- Accessibility text sizes reflow rows vertically and preserve labeled actions.

### iPad and regular width

- App destinations remain in a fixed top tab bar using `tabBarOnly`.
- The app tab bar cannot be transformed into another sidebar.
- Artifact results use a responsive grid.
- Selecting an artifact opens a resizable trailing inspector; it does not push the entire canvas away.
- Artifact never adds a navigation sidebar. Existing workspace sidebars remain the only side navigation in Pines.

## Navigation contract

```text
Pines tab bar -> Artifact Desk
                  |-- scope/refine -> same canvas
                  |-- select item -> inspector (iPad) / sheet (iPhone)
                  |-- New -> command deck -> focused composer
                  `-- active research -> research task sheet
```

The desk must not add horizontal category tabs, a nested `NavigationStack` path for its primary flows, or a research-history page. Provider administration continues to hand off directly to Settings, and provider-hosted file management remains in Vault.

## Density and accessibility rules

- One primary action per surface.
- Controls must have text labels unless space is genuinely constrained.
- A phone result must not consume the full viewport solely for decoration.
- Active work is secondary to completed output and disappears when empty.
- Long titles wrap; controls reflow with `ViewThatFits`; accessibility sizes fall back to stacked rows.
- Selection must be visible on iPad and must not depend on color alone for assistive technology.
