# Pines MCP Support

Pines can connect to remote MCP servers over Streamable HTTP. The implementation is intentionally user-driven: tools, resources, prompts, and sampling are enabled per server from Settings. Selected resources and invoked prompts can enter normal chat context; MCP tools are registered for tool-enabled agent paths and MCP sampling but are not advertised to normal chat by default.

Implementation ownership:

- `MCPStreamableHTTPClient.swift` handles transport state, session headers, JSON-RPC request/notification flow, OAuth exchange, event parsing, and local-network HTTP policy.
- `MCPStreamableHTTPPayloads.swift` contains wire DTOs and JSON helper conversions.
- `MCPServerService.swift` coordinates configured servers, discovered tools/resources/prompts, subscriptions, selected resources, and sampling review state.

## Supported Transport And Auth

- Transport: MCP Streamable HTTP.
- Session handling: `Mcp-Session-Id` is reused after initialization, and sessions can be terminated with `DELETE` when supported.
- Protocol header: Pines sends `MCP-Protocol-Version` after initialization.
- Auth modes: none, static bearer token, and OAuth PKCE.
- OAuth discovery: Pines can discover protected-resource metadata, authorization-server metadata, and dynamically register a public PKCE client when the server supports dynamic client registration.
- Secret storage: bearer tokens, OAuth access tokens, and OAuth refresh tokens are stored in Keychain only.

Remote production servers should use HTTPS. Plain HTTP is intended only for explicit local development endpoints that the app allows as insecure local HTTP.

## Tools

Pines supports MCP tools as registered, policy-gated functions. Enabled MCP tools are namespaced and added to the shared `ToolRegistry`, but normal chat currently keeps its advertised tool list empty unless a future tool mode opts in.

Server methods used:

- `tools/list`
- `tools/call`
- `notifications/tools/list_changed`

Tool schemas are preserved as raw JSON Schema. Pines namespaces tool names as `mcp.<server>.<tool>` before registering them, so server tool names can be stable without colliding with built-in tools.

Tool calls are treated as network operations and go through approval/policy checks. Tool outputs are capped before being returned to model context.

## Resources

Pines supports MCP resources as user-selected context.

Server methods used:

- `resources/list`
- `resources/templates/list`
- `resources/read`
- `resources/subscribe`
- `resources/unsubscribe`
- `notifications/resources/list_changed`
- `notifications/resources/updated`

Resources are never automatically injected into chat context. Users select resources in Settings. Selected text resources are read through the MCP server and inserted as external context at send time. Settings provides a tabbed server detail editor with resource search, template filtering, read preview, attach-to-chat toggles, and subscription toggles when the server supports subscriptions.

Binary/blob resources are decoded only after validation:

- Maximum decoded attachment size is 10 MB.
- Allowed image MIME types: `image/png`, `image/jpeg`, `image/webp`, `image/gif`.
- Allowed document MIME types: `application/pdf`, `text/plain`, `text/markdown`, `text/x-markdown`, `application/json`, `text/csv`.
- Unknown or unsafe binary MIME types are blocked and reported as blocked previews instead of being written to disk.
- Accepted blobs are written to temporary local files and passed as typed `ChatAttachment` values.

Recommended server behavior:

- Provide clear `name`, `title`, `description`, `mimeType`, and `size` values.
- Prefer custom resource URI schemes for server-managed data.
- Use `text/*`, `application/json`, or `text/markdown` for resources intended to enter model context.
- Emit `notifications/resources/list_changed` when resource lists change.
- Emit `notifications/resources/updated` for subscribed resources.

## Prompts

Pines supports MCP prompts as user-invoked templates.

Server methods used:

- `prompts/list`
- `prompts/get`
- `notifications/prompts/list_changed`

Prompts appear in Settings and the chat composer prompt menu. Both entry points render prompt arguments as editable fields before invocation. Pines fetches the prompt, renders its returned messages as chat input, and preserves embedded text and supported image content as local context. Required prompt arguments are checked locally before `prompts/get`; servers should still validate missing or invalid arguments and return JSON-RPC invalid params errors.

Recommended server behavior:

- Keep prompt names stable.
- Include `title`, `description`, and argument descriptions.
- Return `text` content for broad compatibility.
- Use embedded resources when the prompt depends on server-managed context.

## Sampling

Pines supports server-initiated `sampling/createMessage` only when sampling is enabled for the MCP server and the user approves the request.

Server method handled:

- `sampling/createMessage`

Execution boundary:

- Local models are tried first.
- BYOK providers may be used only when BYOK sampling is enabled for that server.
- Global chat execution mode is not used implicitly for sampling.

Pines shows the requesting server, prompt, model preferences, tool count, context intent, and max-token intent before generation. Users can edit the prompt before execution and must review the generated response before it is returned to the MCP server. Approval, denial, and return/block decisions are written to the local audit log with prompt bodies and result bodies redacted.

Model selection uses MCP `modelPreferences` where provided. Pines ranks installed local models first using model hints plus cost, speed, and intelligence priorities. If local execution fails and BYOK sampling is enabled, Pines ranks enabled BYOK providers with the same hints and provider capability checks. Global chat execution mode is not used implicitly for sampling.

Audio sampling content is rejected with a JSON-RPC error. Text and image content are converted to Pines chat messages where the selected provider supports them. Sampling tool definitions supplied by the MCP server are forwarded to the selected local or BYOK provider; the MCP server remains responsible for executing its own tool loop.

Per-server controls:

- Enable or disable sampling.
- Allow or block BYOK cloud sampling.
- Set a maximum number of sampling requests per app session.

Pines only advertises the `sampling` client capability when sampling is enabled for the server configuration. It never advertises `roots` in the current implementation.

Recommended server behavior:

- Use sampling sparingly.
- Keep `maxTokens` bounded.
- Include clear `systemPrompt` and `includeContext` values.
- Do not assume cloud execution is available.
- Be prepared for user denial or provider errors.

## Roots

Pines does not currently support MCP roots and does not advertise `roots` during initialization. Read-only, user-selected roots may be added later behind a separate permission model.

## Server Author Checklist

- Expose one Streamable HTTP MCP endpoint.
- Implement `initialize` and return accurate server capabilities.
- Use `tools`, `resources`, and `prompts` capabilities only when implemented.
- Use `sampling/createMessage` only after seeing the client advertise `sampling`.
- Prefer HTTPS for Mac, LAN, VPS, and SaaS deployments.
- Provide OAuth protected-resource metadata for remote authenticated deployments.
- Avoid returning secrets or oversized resource contents.
- Expect Pines to require explicit user action before resources enter context or sampling runs.

## Example Server Shape

A server that fully leverages Pines should provide:

- Tools for actions, with complete JSON Schema input schemas.
- Resources for readable server context, with stable URIs and MIME metadata.
- Resource templates when URI construction is useful to users or prompt authors.
- Prompts for reusable workflows, with explicit argument metadata.
- Sampling only for workflows that genuinely need client-side model generation.

Minimal capability example:

```json
{
  "capabilities": {
    "tools": { "listChanged": true },
    "resources": { "subscribe": true, "listChanged": true },
    "prompts": { "listChanged": true }
  }
}
```

Sampling should be requested only after initialization shows the client advertised:

```json
{
  "capabilities": {
    "sampling": {}
  }
}
```
