<p align="center">
  <img src="Pines/Assets.xcassets/AppIcon.appiconset/Icon-1024.png" alt="Pines logo" width="144" height="144">
</p>

<h1 align="center">Pines</h1>

<p align="center">
  <strong>Your local-first AI workbench for iOS. Quiet when it should be. Powerful when you ask it to be.</strong>
</p>

<p align="center">
  <a href="https://github.com/RNT56/pines/actions/workflows/ci.yml"><img src="https://github.com/RNT56/pines/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-informational" alt="License: PolyForm Noncommercial 1.0.0"></a>
</p>

Most AI apps feel like a room you visit.

You bring a file. You bring a question. You bring a piece of work that already had a life before the app arrived. Then the app asks you to trust a route you cannot see, a memory you cannot inspect, and a cloud you did not exactly choose.

Pines is built from a different instinct.

It treats your phone like a real computer. It keeps the model close when local is enough. It lets cloud models help when you deliberately invite them. It gives your documents a private vault instead of turning every note into a remote dependency. It connects to tools and MCP servers, but with gates you can understand.

Pines is not trying to be the loudest AI product in the room. It is trying to be the one you keep reaching for because it respects the shape of your work.

## The Feel

Open Pines and the first promise is simple: your workspace belongs to you.

Chats are where the thinking starts. Attach an image, a PDF, a Markdown note, a JSON file, a CSV, or plain text, and ask the question the work actually needs. Pines is built for those normal, messy moments where useful context lives across files, notes, models, and memory.

The vault is where your material becomes reachable without becoming public. It is not a mystical memory layer. It is a place for your documents, chunks, and retrieval to stay grounded.

Models are treated like tools, not subscriptions. You can discover MLX-ready models, install them, and see the route Pines is taking. When cloud makes sense, bring your own key and choose that path on purpose.

Tools are not hidden trapdoors. Search, browser actions, agent flows, and MCP servers live behind visible policy. If something wants context, network access, or a meaningful action, Pines is designed to make that boundary legible before it crosses it.

## Local First, Not Local Only

Local-first does not mean pretending the cloud is useless.

It means the default center of gravity is yours. Your chats, vault, attachments, model state, and private context start on device. Cloud providers are optional, BYOK, and explicit. Private vault or MCP context does not quietly ride along just because a remote model might be convenient.

That distinction matters. A good assistant should know when to help, and it should also know when to ask.

## A Workbench With Trails

Pines brings together the pieces that usually live in separate apps:

- local MLX inference for on-device model work
- BYOK cloud routing for OpenAI-compatible providers, OpenRouter, Anthropic, and Gemini
- a private vault for document context and retrieval
- attachments for images, PDFs, and common text-like files
- MCP Streamable HTTP for tools, resources, prompts, and user-approved sampling
- policy-gated tools for search, browser work, calculator use, and agent flows
- optional private iCloud sync when you choose to widen the boundary
- a theme system that lets the app feel personal without becoming noisy

The result is not a chatbot with a few extras taped on. It is a place to explore, compare, ask, revise, inspect, and keep moving.

## The Personality

Pines is deliberately calm.

It does not need to turn every feature into a spectacle. The best version of this app feels like a clear desk, a sharp pencil, and a window cracked open just enough for air. You should know where your keys are. You should know when a model is local. You should know when a tool is about to act. You should be able to bring in more power without giving up the room.

That is the line Pines keeps walking: capable without being slippery, private without being isolated, technical without making the user feel like a sysadmin just to ask a good question.

## For Builders

Pines is source-available. If you want to build it, audit it, understand the architecture, or work on the internals, start with the [Developer README](DEV_README.md).

Useful field notes:

- [Security And Privacy](docs/SECURITY.md)
- [MCP Support](docs/MCP.md)
- [Design System](docs/DESIGN_SYSTEM.md)
- [Architecture](docs/ARCHITECTURE.md)

## License

Pines is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE) (`PolyForm-Noncommercial-1.0.0`). Commercial use requires a separate written license from Schtack.

Redistributions must preserve the required notices in [NOTICE](NOTICE). Third-party dependencies keep their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
