<p align="center">
  <img src="Pines/Assets.xcassets/AppIcon.appiconset/Icon-1024.png" alt="Pines logo" width="144" height="144">
</p>

<h1 align="center">Pines</h1>

<p align="center">
  <strong>A local-first AI workbench for iOS 26, built for people who want the model close, the keys in their own pocket, and the exits clearly marked.</strong>
</p>

<p align="center">
  <a href="https://github.com/RNT56/pines/actions/workflows/ci.yml"><img src="https://github.com/RNT56/pines/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-informational" alt="License: PolyForm Noncommercial 1.0.0"></a>
</p>

Most AI apps ask you to move out of your own workspace.

You upload the file. You paste the secret. You hope the context goes only where you meant it to go. You hope the model choice was sensible. You hope the app remembers that "private" should mean more than "we wrote a paragraph about it."

Pines starts from the other end.

It treats the phone as a real computer. Local models are the default path. Your vault is local. Your model installs are visible. Cloud is not forbidden, but it is invited deliberately: bring your own key, choose the route, approve the context that leaves the device. Tools, MCP servers, browser actions, and agent work are not magical side doors. They are gates with labels.

That is the personality of Pines: quiet power, visible choices, and fewer moments where you have to wonder what just happened.

## What Pines Is

Pines is a source-available iOS 26 AI workbench built around MLX Swift inference, BYOK cloud providers, private vault context, MCP Streamable HTTP, and a SwiftUI app shell that is meant to feel like a place you can stay in.

It is for the person who wants a capable AI companion without handing over the whole desk. A developer reading logs. A researcher comparing notes. A builder carrying models around like tools, not like subscriptions. Someone who likes cloud models when they help, but does not want every thought routed through them by accident.

Pines is also honest about where it is: this repository is a working foundation, not a finished App Store product. The architecture is real, the local-first boundary is real, and many of the hard parts are already shaped. Production polish, broader device acceptance, and final App Store hardening are still in progress.

## A Walk Through The Woods

### Chat That Knows Its Boundaries

Start with a conversation. Add an image, PDF, Markdown file, JSON file, CSV, or text note. If you send attachments without a prompt, Pines turns that into an explicit analysis request instead of pretending empty text was meaningful.

Local routes are preferred by default. If you choose a BYOK cloud provider, Pines does not silently fall back or smuggle local vault context into the request. When private context would leave the device, you get a per-turn choice: include it, or continue without it.

### Models You Can See

Pines can discover MLX-tagged models from Hugging Face, classify preflight compatibility, and manage resumable installs. Curated models live beside discoverable ones, so the app can offer a known trail without hiding the wider forest.

The app links maintained Schtack MLX forks because Pines depends on TurboQuant and compatibility APIs that are not assumed to exist in upstream releases yet. That choice is intentional, pinned, and checked in CI.

### A Vault That Stays Yours

The vault is where local knowledge becomes useful context. Pines ingests files, chunks them, stores embeddings locally, and retrieves with compressed TurboQuant vector codes plus FP16 rerank. SQLite FTS remains there when embeddings are missing.

The point is not to build a black box of "memory." The point is to make your own material reachable without turning every note into a cloud upload.

### Tools With Permission Slips

Pines has a typed tool registry, local calculator tool, Brave Search BYOK support, and a WKWebView browser runtime. Tool specs include schemas, permissions, side-effect levels, network policy, timeouts, and explanation requirements.

Agent mode gets explicitly enabled tools. Normal chat does not advertise every registered tool by default. Browser and remote-state-changing actions require visible approval. That might sound less flashy than "autonomous agents," but it is a better way to keep your hands on the wheel.

### MCP Without The Fog

Pines connects to MCP servers over Streamable HTTP with support for tools, resources, prompts, subscriptions, OAuth PKCE, bearer tokens, and user-approved sampling.

Resources are selected by the user before they become context. Prompts are invoked deliberately. Sampling requests show what the server is asking for before anything runs, and the generated response is reviewed before it goes back to the server.

### A Theme System With A Pulse

Evergreen, Graphite, Aurora, Paper, Slate, Porcelain, Sunset, and Obsidian are not just color names bolted onto a settings page. The design system is token-driven, environment-injected, and shared across the SwiftUI surface so Pines can feel calm without becoming bland.

## The Promises

- Local-first is the default product boundary.
- BYOK cloud routing is explicit, never a silent escape hatch.
- API keys, MCP bearer tokens, and OAuth tokens belong in Keychain.
- Vault documents, embeddings, attachments, chats, and model state stay on device unless the user opts into a wider boundary.
- iCloud sync is optional and private-database based; generated embeddings and compressed vector codes sync only behind a separate toggle.
- Tools are deny-by-default and policy-gated.
- MCP resources and sampling require user action before they affect chat or leave the app.
- The repo should remain understandable enough that another developer can challenge the boundary, not just trust the README.

## Where It Stands

Pines is not pretending to be finished. The working foundation is here: the app shell, local persistence, model discovery, MLX bridge points, BYOK providers, vault ingestion, tool policy, MCP support, optional CloudKit sync, Watch support, diagnostics, and CI validation.

The rough edges are also named in public: real-device TurboQuant acceptance across the full target hardware matrix, production UX hardening, CloudKit conflict polish, provider editing, model compatibility messaging, and final App Store privacy validation.

That matters because trust is not a vibe. It is a thing you should be able to inspect.

## For Builders

If you want to build Pines, audit the architecture, move the MLX pins, run CI-equivalent checks, or understand the repository layout, start with the [Developer README](DEV_README.md).

The shorter field notes are here:

- [Architecture](docs/ARCHITECTURE.md)
- [Design System](docs/DESIGN_SYSTEM.md)
- [Security And Privacy](docs/SECURITY.md)
- [MCP Support](docs/MCP.md)
- [TurboQuant](docs/TURBOQUANT.md)
- [Implementation Status](docs/STATUS.md)

## License

Pines is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE) (`PolyForm-Noncommercial-1.0.0`). You may use, modify, and redistribute this repository only for permitted noncommercial purposes under that license. Commercial use requires a separate written license from Schtack.

Redistributions must preserve the required notices in [NOTICE](NOTICE). Third-party dependencies keep their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
