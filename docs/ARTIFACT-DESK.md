# Artifact Gallery UX System

## Performance contract

- The library derives provider and research labels from pre-indexed dictionaries rather than scanning those arrays once per artifact.
- Search derivation is cancellable and debounced outside the SwiftUI render path; ordering remains deterministic.
- Activity and research polling are keyed by stable operation IDs, independent of filters, and run through one cancellable scheduler per operation with backoff, jitter, and terminal exit.
- Thumbnails and previews use `PinesImagePipeline`: ImageIO downsampling occurs off-main, duplicate requests coalesce, remote responses are bounded, and the decoded cache is capped by cost.
- Embedded base64 payloads are decoded only after an image-cache miss. Cells do not call `UIImage(data:)` or `AsyncImage`.
- Performance acceptance uses the canonical Artifact journey in [`docs/performance/RUNBOOK.md`](performance/RUNBOOK.md).

## Product model

Artifacts is a zero-navigation gallery. The root is for scanning output, not managing a dashboard. Search, filter, creation, active work, and inspection stay available without becoming permanent panels or nested destinations.

The system has four layers:

1. **Native toolbar** — filter, search, and New use familiar platform controls in the navigation bar.
2. **Running line** — active media and research collapse into one transient summary above the collection and disappear when idle.
3. **Gallery** — one uniform, mixed-output collection for images, video, speech, and reports.
4. **Quick Look** — every artifact opens in a dismissible sheet, including on iPad.

Output types are facets of the same collection, never pages, tabs, or navigation destinations. Filtering changes the collection in place.

## Browse and create flow

- Search uses the native searchable surface and follows the platform's scroll-collapse behavior instead of adding a custom field or search page.
- Filter opens one direct menu containing type, provider, and sort choices. Active filters are visible through the filled filter icon and the collection label; Clear returns to the full collection.
- New opens a direct menu for Image, Video, Speech, or Research. Choosing an item opens its focused composer immediately.
- Creation sheets hold provider, model, setup, and advanced controls. They do not repeat gallery navigation.
- Research resumes or starts in its focused conversation sheet. History remains contextual rather than becoming another page.

There is no command deck between intent and composer, no custom command strip, and no permanent filter panel.

## Image Studio

Image generation is a canvas-first studio rather than a settings form:

- the selected provider and model remain visible in one quiet engine row;
- a proportion-aware canvas establishes the requested output shape before generation;
- the prompt lives in a floating composer dock modeled on the chat composer;
- size and quality are direct composer controls, while provider, model, format, and the complete option set live in one focused settings sheet;
- generated images replace the empty canvas with a visual session grid and open through the same Quick Look system as the library;
- remix mode keeps the reference image visible as the working canvas instead of reducing it to a filename field.

The studio must not duplicate settings buttons, place the prompt in a generic form section, or separate the primary Generate action from the prompt.

## Research workspace

Research is a conversation-first workspace:

- the empty state explains the outcome and offers a small, horizontally scrolling set of useful starting briefs;
- the question or follow-up is entered in a floating chat-style composer pinned to the safe area;
- only the composer surface has chrome—there is no full-width colored or material box behind it;
- source scope and depth remain directly adjustable beside the send action;
- provider/model, source policy, depth, and report structure use a purpose-built setup sheet rather than a generic Form;
- optional clarification uses a focused “Shape the Brief” sheet before any provider request is sent;
- active work reads as a conversation: user question, flat status/progress response, expandable evidence, then a distinct final-report preview.

History remains a toolbar menu and follow-ups stay in the same research thread. Neither becomes another internal page or tab.

## Gallery language

At standard text sizes, an item is an unframed gallery cell:

- a consistently proportioned preview;
- a two-line title;
- one quiet metadata line;
- a compact overflow action.

The thumbnail may use a subtle surface to establish its bounds. The full item does not receive another card, border, shadow, status badge, or decorative container. Mixed media keeps one rhythm instead of becoming a set of competing card designs.

At accessibility text sizes, the gallery becomes a separator-based list. This preserves readable titles and action targets without forcing large text into narrow columns.

## Quick Look

Selecting an item presents a sheet over the unchanged gallery on every device. Quick Look contains:

- a bounded preview;
- title and quiet metadata;
- relevant primary actions;
- collapsible provenance;
- report content, when present.

Regular width may arrange preview and information in two columns inside the sheet. It must not use an inspector or trailing rail: Pines already has app-level side navigation on iPad, and artifact inspection must not squeeze the gallery into another column.

## Responsive contract

### iPhone and compact width

- The gallery uses two balanced columns at standard text sizes.
- Active work stays in one compact summary line; tapping it opens the individual jobs.
- Quick Look, creation, and research use large dismissible sheets.
- Image and Research composers float above their canvas without a full-width footer background.
- Accessibility sizes switch to full-width separator rows and stacked running items.

### iPad and regular width

- The app remains `tabBarOnly`; its header navigation cannot transform into a sidebar.
- The gallery uses an adaptive grid with roughly 205–270 point cells, filling the available canvas without oversized orphan cards.
- Active work remains one slim summary line with no extra cards or rail.
- Quick Look is a centered sheet with an internal two-column layout where space allows.
- Image Studio and Research keep their floating composers centered and bounded instead of stretching controls across the display.
- Artifact adds no sidebar, inspector, or nested navigation rail.

## Theme contract

- The gallery, Quick Look, Image Studio, Video, Speech, Research, setup sheets, clarification, previews, progress, and empty/error states consume `\.pinesTheme` through shared Pines surfaces and controls.
- App-owned separators, loading indicators, press states, fields, buttons, navigation backgrounds, typography, borders, shadows, and motion use theme primitives rather than feature-local styling.
- Platform-owned search, menus, confirmation dialogs, and menu separators remain native for accessibility and interaction fidelity; their accent and surrounding navigation or sheet chrome come from the active Pines theme.
- Video and Speech settings use the same focused Pines setup language as Image and Research rather than falling back to a generic form.
- Source-contract tests reject feature-local system fonts, plain button styles, literal hairlines, and raw status colors in Artifact views. Every theme template resolves in light and dark, and UI coverage renders the Artifact gallery across the complete template and appearance matrix.

## Navigation contract

```text
Pines tab bar -> Artifacts gallery
                  |-- search/filter -> same gallery
                  |-- select item -> Quick Look sheet
                  |-- New -> direct outcome menu -> focused composer sheet
                  `-- running item -> relevant status or research sheet
```

Provider configuration continues to hand off to Settings. Provider-hosted file management remains in Vault.

## Quality rules

- Finished work dominates; running work is secondary and vanishes when empty.
- The root has no stacked hero, dashboard, card wall, category tabs, or duplicated title.
- One interaction should separate New from a chosen composer.
- Image generation stays canvas-first; Research stays conversation-first.
- Floating composers expose one primary action and never sit inside an additional colored footer box.
- Long titles wrap without changing the gallery's preview rhythm.
- Core controls remain reachable with large text, dark appearance, VoiceOver labels, keyboard navigation, and pointer input.
- Every Pines theme template must preserve readable contrast, hierarchy, and gallery rhythm in both light and dark appearance.
- iPad gains density and breathing room, not another navigation system.
