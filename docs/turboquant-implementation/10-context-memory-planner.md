# Context Memory Planner

Context virtualization is the first product unlock after the control-plane runtime is safe. It replaces blunt truncation with an explicit memory hierarchy and a recorded context assembly decision.

Launch wave: Minimal `ContextAssemblyPlan.v1` metadata is part of Wave 2 bridge integration; full context planner work is Wave 4 after MVP 1.5 evidence gate.

## Principle

Users do not care about token counts. They care that the assistant remembers the document, project, task, and constraints.

The product should behave like:

```text
pinned prefix
+ hot recent tokens
+ compressed KV cache
+ cold semantic memory
+ summaries
+ retrieval
= one apparent long memory
```

The core innovation is deciding what deserves live KV residency and what should be represented by retrieval, summaries, or later exact-prefix snapshots.

## Critical distinction

Semantic memory and KV state are not interchangeable.

- Semantic memory: summaries, retrieved chunks, user facts, document snippets, tool outputs. These can be inserted into a future prompt.
- KV snapshots/pages: model-specific attention state. These are valid only when model, tokenizer, profile, RoPE config, and exact token prefix match.

Warm compressed KV pages must never be treated as generic retrieval chunks.

## MVP 1 minimal ContextAssemblyPlan.v1

MVP 1 records current behavior without requiring full context virtualization:

```swift
public struct ContextAssemblyPlan: Codable, Sendable {
    public var schemaVersion: Int
    public var planID: String
    public var tokenBudget: Int
    public var plannedTokens: Int
    public var exactInputTokens: Int?
    public var pinnedSegments: [ContextSegment]
    public var liveRecentSegments: [ContextSegment]
    public var retrievedSegments: [ContextSegment]
    public var summarizedSegments: [ContextSegment]
    public var droppedSegments: [ContextSegment]
    public var clippedMessageIDs: [String]
    public var explanation: String
}
```

MVP 1 states:

- pinned prompt/system instructions;
- included recent messages;
- clipped messages;
- exact token count;
- truncation reason.

## MVP 2 full planner

```swift
public struct ContextSegment: Codable, Sendable, Identifiable {
    public var id: UUID
    public var source: ContextSegmentSource
    public var role: ContextSegmentRole
    public var estimatedTokens: Int
    public var exactTokenRange: Range<Int>?
    public var priority: Double
    public var recencyScore: Double
    public var retrievalScore: Double?
    public var lastAttentionMass: Double?
    public var storageState: ContextStorageState
    public var canSummarize: Bool
    public var canEvictKV: Bool
    public var provenance: ContextSegmentProvenance
}

public enum ContextStorageState: String, Codable, Sendable {
    case pinnedPrompt
    case liveRecent
    case retrievedVault
    case summary
    case dropped
    case compressedKVPage
}
```

Segment roles:

- system instruction;
- user preference;
- tool schema;
- recent user message;
- recent assistant message;
- older chat;
- vault evidence;
- tool output;
- summary;
- snapshot reference.

## Planner inputs

The planner consumes:

- chat messages;
- system prompt;
- tool schemas;
- user preferences;
- vault retrieval results;
- summaries;
- active task/tool state;
- token budget from admission;
- privacy route decision;
- user mode;
- evidence and memory constraints.

## Planner output

The planner emits:

- pinned segments;
- live recent segments;
- retrieved segments;
- summarized segments;
- dropped segments;
- token budget;
- planned token count;
- explanation;
- provenance for sources and privacy boundary.

## Segment scoring

Initial scoring should combine:

- role priority;
- recency;
- retrieval score;
- user pinning;
- task relevance;
- tool-output freshness;
- summary availability;
- privacy eligibility;
- token cost.

Do not use attention mass as a required MVP 2 input. Add it later when runtime can report it cheaply and reliably.

## Storage-state rules

### Pinned prompt

Includes:

- system prompt;
- model identity/personality constraints;
- user preferences that must always apply;
- required tool schemas;
- active security/policy constraints.

Rules:

- never summarized;
- never dropped silently;
- high precision when adaptive precision exists.

### Live recent

Includes:

- latest user turns;
- latest assistant turns;
- active task instructions.

Rules:

- preferred live KV residency;
- clipped only after pinned and evidence budgets are satisfied;
- clipping is recorded.

### Retrieved vault

Includes:

- selected document chunks;
- local notes;
- source-code snippets;
- PDFs/transcripts;
- citations.

Rules:

- scoped by retrieval budget;
- provenance recorded;
- cloud route requires explicit approval before local vault content is sent out.

### Summary

Includes:

- local summaries of older turns;
- project notes;
- memory summaries.

Rules:

- summary provenance recorded;
- user can inspect summary;
- summary should not claim exactness where exact source was dropped.

### Dropped

Includes:

- low-priority old context;
- over-budget retrieved chunks;
- superseded tool output.

Rules:

- record why dropped;
- user can see count/reason;
- no silent loss of pinned constraints.

### Compressed KV page

Future state for exact-prefix valid compressed KV pages.

Rules:

- valid only with exact identity and prefix;
- not a semantic retrieval chunk;
- can restore session state only through snapshot validation.

## Vault retrieval budget

`RetrievalContextPlan`:

```swift
public struct RetrievalContextPlan: Codable, Sendable {
    public var selectedVaultChunks: [UUID]
    public var liveTokenBudget: Int
    public var summaryBudget: Int
    public var evidenceBudget: Int
    public var pinnedBudget: Int
    public var citationBudget: Int
}
```

Rules:

- retrieved evidence should have higher precision in adaptive policies;
- citations require source provenance;
- local-only vault content cannot be included in cloud requests without approval.

## UI requirements

User-visible:

- context reduced reason;
- what sources were included;
- what was summarized;
- what was dropped;
- whether local vault content was used.

Technical details:

- token budgets;
- segment IDs;
- storage states;
- retrieval scores;
- exact token count;
- context plan schema/version.

## Tests

Required:

- deterministic plan for same inputs;
- pinned prompt cannot be dropped;
- cloud route excludes vault chunks without approval;
- dropped segments record reason;
- summary segments record provenance;
- compressed KV page cannot be used without exact prefix validity;
- MVP 1 minimal plan can be emitted from existing truncation metadata.
