# GitHub Repo Description And Landing Page Plan

This document contains GitHub-ready repository copy and a practical landing-page plan for a Netlify-hosted Pines product site.

## GitHub Repository Metadata

### Short Description

Use this in GitHub's repository description field:

> Local-first AI workbench for iOS and Apple Watch: MLX on-device models, BYOK cloud providers, private vault context, MCP tools, and policy-gated agents.

Alternative, slightly more technical:

> Source-available SwiftUI AI workbench for iOS and watchOS with local MLX inference, BYOK cloud routing, private vault retrieval, MCP, agents, and Watch support.

Alternative, slightly more product-led:

> Pines is a local-first AI workbench for iOS and Apple Watch that brings on-device models, cloud specialists, private context, and tools into one app.

### Website URL

Add the Netlify landing page once live:

```text
https://pines-ios-ai.netlify.app
```

If you configure a custom domain later, replace the Netlify URL with that production URL.

### Topics

Suggested GitHub topics:

```text
ios
watchos
swift
swiftui
mlx
mlx-swift
local-ai
on-device-ai
llm
vlm
rag
mcp
ai-agents
byok
cloudkit
grdb
huggingface
privacy
mobile-ai
source-available
```

### Social Preview

Use a clean product preview rather than a code screenshot:

- App icon on a quiet Evergreen or Obsidian background.
- iPhone app screenshot showing Chats, Models, or Vault.
- Apple Watch screenshot beside it showing a live chat or conversation list.
- Short line: `The AI workbench you own.`

Avoid claiming App Store availability until the app is actually ready for public distribution.

## Long Repository Overview

Use this as a GitHub About/README summary, release-page intro, or pinned issue description.

> Pines is a source-available local-first AI workbench for iOS and Apple Watch. It is built around local MLX Swift inference, bring-your-own-key cloud routing, private vault context, MCP tools, policy-gated agent workflows, GRDB persistence, optional CloudKit sync, and a SwiftUI interface designed for serious mobile AI work.
>
> The project treats the iPhone as a real AI computer, not just a remote control for cloud chat. Local models can answer directly on device, private files can live in a searchable vault, and stronger cloud providers can be added explicitly when a task needs them. Pines never silently falls back from local execution to cloud execution; provider choice and private-context sharing are visible user decisions.
>
> Pines currently includes an iOS app, a watchOS companion, shared core Swift packages, model discovery and install flows, vault ingestion with OCR and embeddings, BYOK adapters for OpenAI-compatible endpoints, OpenRouter, Anthropic, and Gemini, MCP Streamable HTTP support, policy-gated tools, audit events, and release/CI validation scripts. It is a working production-oriented foundation rather than a finished App Store client.

## Positioning

### Core Promise

Pines gives people one place to use local models, private context, trusted cloud specialists, and tools without handing the whole workflow to one vendor.

### Audience

- New AI users who want one clear app instead of provider sprawl.
- Power users who compare local models, cloud models, context windows, and tool protocols.
- Developers and researchers who want to inspect, build, or extend a serious mobile AI stack.
- Privacy-minded users who want local-first behavior and explicit cloud boundaries.

### Differentiators

- Local-first iOS inference through MLX Swift.
- BYOK cloud routing across multiple provider families.
- No silent local-to-cloud fallback.
- Private vault for documents, chunks, OCR, embeddings, retrieval, and local context.
- MCP Streamable HTTP support for tools, resources, prompts, subscriptions, and user-approved sampling.
- Policy-gated tools and audit events instead of invisible agent actions.
- Watch companion for quick chat access, replies, cancellation, conversation management, and status.
- Source-available SwiftUI codebase with GRDB, CloudKit, XcodeGen, and CI validation.

## Landing Page Goal

Build a fast, app-like product site that makes Pines feel like a real mobile AI workspace, not a generic AI landing page. The page should help visitors understand:

- What Pines is.
- Why local-first mobile AI matters.
- How local models, cloud providers, vault context, MCP, agents, iPhone, and Apple Watch fit together.
- What is available today versus still in progress.
- Where to go next: GitHub, docs, releases, TestFlight or waitlist when available.

## Recommended Site Stack

Use an Astro site under `site/`.

Reasons:

- Static output works cleanly on Netlify.
- SEO and Open Graph metadata are straightforward.
- Content pages such as privacy, status, and releases can remain Markdown-driven.
- React or vanilla islands can be added only where interaction is useful.
- The app-like visual layer can still be custom CSS without shipping a heavy client bundle.

Suggested structure:

```text
netlify.toml
site/
  astro.config.mjs
  package.json
  public/
    app-icon.png
    pines-mark.svg
    og-image.png
    screenshots/
  src/
    components/
      AppChrome.astro
      DeviceShowcase.astro
      FeatureTabs.tsx
      ModelRail.astro
      ProviderStrip.astro
      WatchCompanion.astro
      PrivacyBoundary.astro
      Roadmap.astro
      CTA.astro
    layouts/
      MarketingLayout.astro
    pages/
      index.astro
      privacy.astro
      status.astro
```

Netlify settings:

```toml
[build]
  command = "npm --prefix site ci && npm --prefix site run build"
  publish = "site/dist"

[[headers]]
  for = "/*"
  [headers.values]
    X-Frame-Options = "DENY"
    X-Content-Type-Options = "nosniff"
    Referrer-Policy = "strict-origin-when-cross-origin"
```

## Page Information Architecture

### 1. Hero

First viewport purpose: identify Pines immediately and show the product.

Content:

- Navigation: Pines mark, GitHub, Docs, Privacy, Releases, primary CTA.
- H1: `Pines`
- Subhead: `The AI workbench you own: local models, cloud specialists, private context, and tools in one iOS home.`
- Primary CTA: `View on GitHub`
- Secondary CTA: `Read the docs`
- Future CTA when ready: `Join TestFlight`
- Visual: iPhone app screenshot and Apple Watch screenshot in a single app-like composition.

Hero notes:

- The brand/product name must be the H1.
- Use real app screenshots as soon as possible.
- Keep the next section slightly visible on desktop and mobile.
- Avoid a generic gradient hero. Use the product UI and app icon as the visual signal.

### 2. Proof Strip

Compact product facts:

- `Local-first by default`
- `MLX on device`
- `BYOK cloud routes`
- `Private vault`
- `MCP tools`
- `Watch companion`

### 3. Product Tour

Use a tabbed or segmented showcase with screenshots.

Tabs:

- Chats: model picker, streaming, attachments, cloud-context consent.
- Models: Hugging Face discovery, verified local model installs, runtime diagnostics.
- Vault: document import, OCR, chunking, embeddings, semantic search.
- Agents: tool approval, Brave Search, browser actions, local data tools.
- Settings: providers, MCP servers, privacy, CloudKit, themes.
- Watch: status, conversation list, quick replies, stop/retry flows.

### 4. Local Models

Explain local inference as a daily workflow, not just a privacy claim.

Draft copy:

> Install verified MLX models, keep small and capable assistants on device, and use runtime guardrails that adapt to memory and thermal pressure. Pines is designed to make mobile local AI feel like an instrument, not a benchmark.

Include:

- Curated model examples.
- Compact/balanced/pro device tiers.
- TurboQuant/runtime diagnostics.
- Vision and embedding model lanes where supported.

### 5. Cloud When It Earns The Trip

Explain BYOK without making it sound like cloud is the default.

Draft copy:

> Add cloud providers when a task needs more reach. OpenAI-compatible endpoints, OpenRouter, Anthropic, and Gemini can sit beside local models, with explicit routing and private-context approval before sensitive material leaves the device.

Include:

- Provider cards.
- Execution modes: local only, prefer local, cloud allowed, cloud required.
- No silent fallback.

### 6. Private Vault

Show context as a durable product surface.

Draft copy:

> Store the files and notes that make an assistant useful. Pines can import images, PDFs, Markdown, JSON, CSV, and text files, chunk them, index them, and retrieve relevant context when a conversation needs it.

Include:

- Import pipeline.
- OCR.
- Local-first storage.
- Embedding profile approval.
- Vault search and read tools.

### 7. Tools And MCP

Make consent the feature.

Draft copy:

> Pines supports policy-gated tools and MCP Streamable HTTP, but tools do not get invisible authority. Network access, private context, browser actions, and server-driven sampling are designed around user approval and local audit events.

Include:

- Built-in tools.
- MCP tools/resources/prompts/sampling.
- OAuth PKCE and bearer tokens in Keychain.
- Resource previews and attach-to-chat toggles.

### 8. Apple Watch Companion

Show the Watch app as a real companion, not a novelty.

Draft copy:

> Keep the conversation close. Pines Watch can list chats, open transcripts, send quick replies, stop active runs, retry pending requests, and manage conversation state through the paired iPhone.

Include:

- Reachability/status diagnostics.
- Quick replies.
- Stop button.
- Rename/archive/delete flows.
- Haptics.

### 9. Built For Builders

Convert technical credibility into confidence.

Include:

- SwiftUI app layer.
- `Sources/PinesCore` contracts.
- GRDB persistence.
- Optional CloudKit sync.
- MLX Swift bridge.
- XcodeGen project.
- Swift Testing and CI scripts.
- Links to architecture, security, MCP, status, and model docs.

### 10. Status And Roadmap

Be explicit and credible.

Recommended framing:

> Pines is a working foundation for a serious iOS AI workbench. It is source-available today, with production-oriented internals already in place, while final App Store hardening and broader device acceptance are still ongoing.

Roadmap blocks:

- Real-device TurboQuant acceptance across A16 through A19 Pro hardware.
- Production UX hardening for regenerate controls and provider editing.
- CloudKit conflict UI.
- Final App Store privacy validation.
- Broader model compatibility messaging.

### 11. Final CTA

Options:

- `View the source`
- `Read the developer README`
- `Follow releases`
- `Join TestFlight` once available
- `Contact RNT56 for commercial licensing`

## Visual Direction

### Product Feel

The landing page should feel like the app: calm, capable, technical, and owned. It should look like a polished product interface, not a SaaS template.

Use:

- App screenshots and device frames.
- Dense but readable product panels.
- A restrained Evergreen-first palette with Obsidian dark sections.
- Small status chips, provider badges, model rows, and tool approval sheets.
- Real UI vocabulary from the app: Chats, Models, Vault, Settings, Agent mode, MCP, BYOK.

Avoid:

- Generic AI orb backgrounds.
- Purple-blue gradient blobs.
- Oversized marketing cards with vague claims.
- Fake provider logos unless rights and display rules are checked.
- Claims that imply public App Store readiness before launch.

### Color Direction

Start from Pines' app identity:

- Pine green primary.
- Soft mint/cyan highlights.
- Graphite or near-black technical surfaces.
- Ivory or porcelain light surfaces.
- Warm warning/accent colors for policy and cloud-boundary moments.

The page should not read as a single-hue green theme. Use neutral surfaces, dark console sections, cyan/mint accents, and a few warm status colors.

### Typography

Use system-first typography:

```css
font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
```

Keep display type restrained. The product screenshots and interface details should do most of the work.

### Interaction

Useful interactions:

- Product tour tabs.
- Model capability filter chips.
- A local/cloud route toggle animation.
- MCP approval flow mini-demo.
- Watch/iPhone connection status demo.
- Theme toggle for light/dark preview.

Keep animations subtle and respect reduced motion.

## Asset Plan

Use existing assets:

- `Pines/Assets.xcassets/AppIcon.appiconset/Icon-1024.png`
- `Pines/Assets.xcassets/PinesMark.imageset/pines-mark.svg`

Create before launch:

- iPhone screenshots for Chats, Models, Vault, Settings.
- Apple Watch screenshots for conversation list and transcript.
- Open Graph image.
- Favicon set.
- Optional short silent video or animated WebM of model switching and vault retrieval.

Screenshot rules:

- Use realistic but non-sensitive sample data.
- Show actual UI states, not generic mockups.
- Include both light and dark examples only when they clarify product depth.
- Do not show real API keys, private documents, or personal provider accounts.

## SEO And Metadata

Primary title:

```text
Pines - Local-first AI workbench for iOS and Apple Watch
```

Meta description:

```text
Pines brings on-device MLX models, BYOK cloud providers, private vault context, MCP tools, and policy-gated agents into one local-first iOS and Apple Watch AI app.
```

Open Graph title:

```text
Pines: The AI workbench you own
```

Open Graph description:

```text
Local models, cloud specialists, private context, and tools in one iOS home.
```

## Supporting Pages

### Privacy

Summarize:

- Local-first defaults.
- BYOK-only cloud execution.
- Keychain-only secrets.
- Optional CloudKit sync.
- Per-turn private context approval.
- MCP and tool approval boundaries.

This can be based on `docs/SECURITY.md` and `docs/APP_STORE_PRIVACY.md`.

### Status

Summarize current implementation state from `docs/STATUS.md`.

Use this page to keep the main landing page confident without hiding unfinished work.

### Releases

Link to GitHub releases and source archives. Mention the PolyForm Noncommercial license and commercial licensing path.

## Accessibility And Performance Checklist

- Lighthouse mobile score target: 95+ performance, accessibility, best practices, SEO.
- All interactive controls keyboard reachable.
- Respect `prefers-reduced-motion`.
- Text contrast passes WCAG AA.
- No layout shift when tour tabs change.
- All screenshots have meaningful alt text.
- Hero image loads eagerly; below-fold images lazy-load.
- Keep initial JavaScript small; static HTML should carry the core message.

## Launch Checklist

- Capture final app screenshots from simulator and Watch simulator.
- Add `site/` with Astro and a repo-root Netlify config.
- Add production domain and canonical metadata.
- Generate OG image.
- Link the site from GitHub repository metadata.
- Link GitHub, docs, status, privacy, and releases from the site footer.
- Confirm license language matches `LICENSE` and `NOTICE`.
- Run a production build locally.
- Test Netlify preview deploy.
- Verify mobile and desktop layouts before publishing.
