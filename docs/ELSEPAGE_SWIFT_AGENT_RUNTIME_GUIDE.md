# Elsepage Swift Agent Runtime Development Guide

> Status: Living architecture guide
> Audience: Codex / human contributors
> Product: Elsepage / 页外
> Scope: Swift Agent Runtime, Reader Agent, providers, tools, context, retrieval, memory proposals, evaluation
> Principle: **Build a small, rigorous Agent Runtime for Elsepage — not a general-purpose agent framework.**

---

## 1. What this runtime is for

Elsepage is not an EPUB reader with a chat box. Its long-term product loop is:

```text
Read → Reflect → Discuss → Remember → Reconnect
```

The Agent system exists to make that loop increasingly valuable over time. The first Reader Agent should help a user understand what they are thinking, connect that thought to the current book, reconnect it with relevant earlier thoughts, ask one useful follow-up question when appropriate, and gradually form an evidence-backed intellectual memory.

The runtime must remain stable as Elsepage later adds multiple providers, structured outputs, tool calling, streaming UI, book RAG, personal memory, curated knowledge, voice input, background workflows, long-term evaluation, and additional Agent roles.

The runtime must **not** be tightly coupled to a provider, SwiftUI screen, database implementation, Readium type, or current MVP flow.

---

## 2. Core architecture

Do not build this:

```text
ReflectionView
    ↓
OpenAIClient
    ↓
HTTP
    ↓
String
```

Build this:

```text
SwiftUI / Product UI
        ↓
Product Use Case
        ↓
ReaderAgent
        ↓
AgentRuntime
 ┌───────────────┬──────────────┬──────────────┐
 │ Context       │ Policy       │ Execution    │
 │ Builder       │              │ Engine       │
 └───────────────┴──────────────┴──────────────┘
        ↓
 ModelClient / ToolRegistry
        ↓
Providers / Retrieval / Persistence
```

### Architectural invariants

1. SwiftUI must never call provider HTTP APIs directly.
2. Provider-specific types must not leak above `ModelProviders`.
3. `AgentRuntime` must not depend on SwiftUI, UIKit, Readium, GRDB, `ReaderCore`, `ReflectionCore`, or `MemoryCore`.
4. `ReaderAgent` may depend on product-domain modules and `AgentRuntime`.
5. User reflection is source-of-truth data and must be persisted before any AI request.
6. AI-generated memory must be proposed and validated; the model never writes permanent memory directly.
7. Provider-hosted conversation state is never canonical history.
8. Cancellation is a normal state, not a generic failure.
9. Prefer deterministic workflows over open-ended loops.
10. Use the minimum necessary degree of agency.

---

## 3. Recommended module layout

```text
Sources/
├── AgentRuntime/
│   ├── Domain/
│   │   ├── AgentRun.swift
│   │   ├── AgentEvent.swift
│   │   ├── AgentInput.swift
│   │   ├── AgentResult.swift
│   │   ├── AgentFailure.swift
│   │   └── JSONValue.swift
│   ├── Execution/
│   │   ├── AgentExecutor.swift
│   │   ├── AgentExecutionState.swift
│   │   ├── ExecutionBudget.swift
│   │   └── CancellationPolicy.swift
│   ├── Models/
│   │   ├── ModelClient.swift
│   │   ├── ModelDescriptor.swift
│   │   ├── ModelCapabilities.swift
│   │   ├── ModelRequest.swift
│   │   ├── ModelEvent.swift
│   │   └── ModelResponse.swift
│   ├── Tools/
│   │   ├── AgentTool.swift
│   │   ├── AnyAgentTool.swift
│   │   ├── ToolRegistry.swift
│   │   ├── ToolInvocation.swift
│   │   └── ToolResult.swift
│   ├── Context/
│   │   ├── AgentContext.swift
│   │   ├── ContextBuilder.swift
│   │   └── ContextBudget.swift
│   ├── Policy/
│   │   ├── AgentPolicy.swift
│   │   ├── PromptTemplate.swift
│   │   └── PromptVersion.swift
│   └── Trace/
│       ├── AgentTrace.swift
│       ├── RunRecorder.swift
│       └── TraceRetentionPolicy.swift
├── ModelProviders/
│   ├── OpenAI/
│   ├── Anthropic/
│   └── OpenAICompatible/
├── ReaderAgent/
│   ├── ReaderAgent.swift
│   ├── ReaderAgentContextBuilder.swift
│   ├── ReaderAgentPolicy.swift
│   └── ReaderAgentTools.swift
├── RetrievalCore/
├── MemoryCore/
└── Persistence/
```

Keep the public API small. If `AgentRuntime` grows into dozens of managers, coordinators, factories, and protocols, the design is drifting toward framework over-engineering.

---

## 4. Streaming-first runtime API

Do not make the primary API:

```swift
func run(...) async throws -> String
```

Prefer:

```swift
protocol Agent: Sendable {
    func run(
        input: AgentInput
    ) -> AsyncThrowingStream<AgentEvent, Error>
}
```

The UI should consume normalized events:

```swift
for try await event in readerAgent.run(input: input) {
    switch event {
    case .textDelta(let text):
        // update visible response

    case .toolStarted(let call):
        // optional subtle activity state

    case .memoryProposed(let proposal):
        // do not persist directly here

    case .completed(let result):
        // finalize product state

    case .cancelled:
        // normal cancellation

    case .failed(let failure):
        // recoverable UI state

    default:
        break
    }
}
```

The UI must not know whether the provider uses Responses, Chat Completions, Anthropic Messages, SSE, provider-specific tool payloads, or JSON-schema output.

### Recommended events

```swift
enum AgentEvent: Sendable {
    case runStarted(AgentRunID)
    case contextPrepared(ContextSummary)
    case modelStarted(ModelCallID)
    case textDelta(String)
    case toolRequested(ToolInvocation)
    case toolStarted(ToolCallID)
    case toolFinished(ToolResult)
    case memoryProposed(MemoryProposal)
    case usageUpdated(TokenUsage)
    case completed(AgentResult)
    case cancelled
    case failed(AgentFailure)
}
```

Do not persist every token delta forever. Release tracing should keep only meaningful events needed for diagnostics and reconstruction.

---

## 5. Swift 6 concurrency rules

### 5.1 Prefer immutable `Sendable` values

Most runtime/domain types should be `struct`/`enum`, immutable, `Codable` where useful, and `Sendable`.

```swift
struct AgentRunID: Hashable, Codable, Sendable {
    let rawValue: UUID
}
```

Avoid mutable reference types unless necessary.

### 5.2 Shared mutable state belongs in actors

```swift
actor AgentExecutor {
    private var activeRuns: [AgentRunID: RunState] = [:]
}
```

Reasonable actor candidates include `AgentExecutor`, `RunRecorder`, and tool execution coordination.

### 5.3 Runtime is not `@MainActor`

Correct separation:

```text
SwiftUI ViewModel  → @MainActor
ReaderAgent        → non-main isolated
AgentRuntime       → non-main isolated
Provider           → URLSession async
```

Do not put the runtime or provider clients on MainActor.

### 5.4 Avoid escape hatches

Do not add `@unchecked Sendable` or `@preconcurrency` simply to silence Swift 6. If required for a third-party library, isolate the workaround, document why it is safe, and add removal conditions.

### 5.5 Cancellation must propagate

Every long-running operation must honor cancellation. Conceptually:

```text
UI dismissal
→ Agent task
→ context retrieval
→ model stream
→ tool execution
→ URLSession
```

Never convert `CancellationError` into “generation failed”.

---

## 6. Model abstraction

Do not use a lowest-common-denominator interface like:

```swift
protocol LLMClient {
    func chat(messages: [Message]) async throws -> String
}
```

Prefer:

```swift
protocol ModelClient: Sendable {
    var descriptor: ModelDescriptor { get }

    func stream(
        request: ModelRequest
    ) -> AsyncThrowingStream<ModelEvent, Error>
}
```

Capabilities should be explicit:

```swift
struct ModelCapabilities: OptionSet, Sendable {
    let rawValue: Int

    static let streaming        = Self(rawValue: 1 << 0)
    static let toolCalling      = Self(rawValue: 1 << 1)
    static let structuredOutput = Self(rawValue: 1 << 2)
    static let reasoning        = Self(rawValue: 1 << 3)
    static let vision           = Self(rawValue: 1 << 4)
}
```

Runtime behavior may adapt to capabilities. Do not pretend every provider has identical semantics.

---

## 7. Normalize semantics, not HTTP

Provider adapters should normalize provider-specific streaming payloads into a common model event stream:

```swift
enum ModelEvent: Sendable {
    case textDelta(String)
    case toolCallStarted(ToolCallID, name: String)
    case toolCallArgumentsDelta(ToolCallID, fragment: String)
    case toolCallCompleted(ToolInvocation)
    case usage(TokenUsage)
    case completed(ModelFinishReason)
}
```

The boundary is:

```text
provider-specific JSON / SSE
        ↓
normalized ModelEvent
```

No provider JSON object may appear in `ReaderAgent`, `AgentRuntime`, or SwiftUI.

### Provider strategy

V1 should support at least an `OpenAICompatibleModelClient` with configurable base URL, model name, options, and a separately resolved credential. Long term, provider-specific adapters may include `OpenAIResponsesClient` and `AnthropicMessagesClient` when their native semantics are worth preserving.

Do not force all providers to impersonate OpenAI internally.

---

## 8. BYOK and credentials

API keys belong in Keychain only.

Never store them in SQLite, UserDefaults, logs, fixtures, generated JSON, or committed files.

Use a flow like:

```text
CredentialStore
    ↓
ProviderFactory
    ↓
ModelClient
```

Provider configuration can contain provider type, base URL, model, and options, but not copy the secret through the app graph.

The reader must remain fully usable with no provider configured.

---

## 9. Execution state machine

Never implement the runtime as an unbounded `while true { callModel(); executeTools() }` loop.

Use an explicit state machine:

```text
idle
  ↓
preparingContext
  ↓
requestingModel
  ↓
streamingModel
  ↓
  ├── final response ─────────→ finalizing
  │
  └── tool calls
         ↓
     executingTools
         ↓
     requestingModel
  ↓
completed
```

Terminal states:

```text
completed
cancelled
failed
budgetExceeded
```

Invalid transitions should be difficult or impossible to express.

---

## 10. Execution budget

Every run must be bounded.

```swift
struct ExecutionBudget: Sendable {
    let maxModelCalls: Int
    let maxToolCalls: Int
    let maxWallTime: Duration
    let maxContextTokens: Int?
    let maxOutputTokens: Int?
}
```

Start conservatively for Reader Agent, e.g. a few model calls and a few tool calls at most.

Elsepage does not need long autonomous chains. If deterministic context + one model call solves the task, do not enter an agent loop.

---

## 11. Typed tools

Avoid `[String: Any]` as the main contract.

```swift
protocol AgentTool: Sendable {
    associatedtype Input: Codable & Sendable
    associatedtype Output: Codable & Sendable

    static var name: String { get }
    var description: String { get }

    func execute(
        _ input: Input,
        context: ToolExecutionContext
    ) async throws -> Output
}
```

Use `AnyAgentTool` only at the registry boundary.

### Tool schema

Every tool must have a machine-readable, versionable JSON Schema contract. Example tool name:

```text
search_personal_thoughts@1
```

Machine-facing model output must be decoded and validated. Never use regex to parse structured output.

### V1 tool surface

Good tools:

```text
get_current_reading_context
search_current_book
get_highlight
search_personal_reflections
get_reflection
search_personal_thoughts
```

Potential later tool:

```text
search_wisdom_library
```

Do not expose arbitrary shell, browser, HTTP, filesystem, SQL, direct memory deletion, or direct database writes.

Agent tools should expose **domain capabilities**, not system capabilities.

---

## 12. Read vs write capabilities

Classify tools:

```swift
enum ToolRisk: Sendable {
    case readOnly
    case proposesMutation
    case mutating
}
```

V1 should strongly prefer read-only tools.

Permanent memory flow:

```text
Agent
  ↓
MemoryProposal
  ↓
MemoryPolicy
  ↓
Validation
  ↓
Persistence
```

The model never directly writes long-term memory.

---

## 13. ReaderAgent is product behavior

The runtime is infrastructure. `ReaderAgent` defines Elsepage's behavior.

```swift
struct ReaderAgent: Sendable {
    let runtime: AgentRuntime
    let contextBuilder: ReaderAgentContextBuilder
    let policy: ReaderAgentPolicy
}
```

Future agents may reuse the runtime, but must not duplicate provider/streaming/tool infrastructure.

### Reader Agent behavior

It should:

1. understand the user's reflection;
2. respond to what the user actually expressed;
3. use nearby book evidence when relevant;
4. reconnect to at most one highly relevant earlier thought when useful;
5. ask at most one useful follow-up question;
6. stay concise by default.

It should not:

- summarize chapters unless asked;
- praise generically;
- fabricate quotes;
- overuse memory;
- pretend certainty;
- turn every reflection into philosophy;
- show off knowledge;
- replace the user's thinking.

Desired tone:

```text
wise
calm
precise
curious
restrained
non-flattering
```

---

## 14. Context architecture

Use layered context:

```text
L0 — Immediate
current reflection
current session
nearby passage

L1 — Book
current chapter
highlights
book retrieval

L2 — Me
previous reflections
questions
ideas
belief revisions

L3 — World
curated / authorized knowledge
```

Priority:

```text
L0 > L1 > L2 > L3
```

Do not maximize context size. Maximize relevance.

### Model-planned, locally enforced context routing

Elsepage uses an LLM for semantic routing because intent such as emotional
recording, author disagreement, or a strong personal connection cannot always be
reliably inferred from keywords. The model is a planner, never a data executor.

Required pipeline:

```text
Reflection
   ↓
LLM proposes strict ContextPlan
   ↓
Swift validates source permissions, read-so-far and budgets
   ↓
retrieve book evidence
retrieve personal evidence
   ↓
rank
   ↓
apply context budget
   ↓
ReaderAgentContext
```

The router must not access repositories, Readium, SQL, FTS, vectors, secrets,
Memory/Profile, or external knowledge. Invalid JSON, timeout, or provider failure
must use a deterministic minimal fallback. The fallback is availability, not a
second product personality.

### Context budget

Never append all available memory. Use an explicit budget. A conceptual allocation might be:

```text
Immediate     35%
Book          30%
Personal      25%
World         10%
```

The exact implementation may use tokens, characters, evidence counts, or provider limits. The invariant is that context size is policy-controlled.

---

## 15. Evidence and provenance

Every retrievable item must have a stable ID.

```swift
struct Evidence: Codable, Sendable {
    let id: EvidenceID
    let source: EvidenceSource
    let text: String
    let locator: EvidenceLocator?
}
```

Possible sources:

```text
BookLocator
HighlightID
ReflectionID
MemoryID
KnowledgeSourceID
```

If the Agent says “this resembles something you wrote last month”, that claim should resolve to a concrete `ReflectionID`.

No invisible provenance.

---

## 16. Prompt architecture

Prompt policy must not live as giant strings inside ViewModels.

Conceptually:

```text
ReaderAgentPolicy
├── identity
├── behavioralRules
├── evidenceRules
├── memoryRules
├── responseStyle
└── outputContract
```

Version prompts and context recipes.

Every Agent run should record:

```text
promptVersion
contextRecipeVersion
toolSchemaVersion
provider
model
```

Without this, quality regressions cannot be diagnosed reliably.

---

## 17. User-facing response vs machine-facing output

Do not make one free-text response serve UI, memory, tags, and connections simultaneously.

Separate natural-language response from structured metadata.

```swift
struct ReaderAgentMetadata: Codable, Sendable {
    let memoryProposals: [MemoryProposal]
    let connectionProposals: [ThoughtConnectionProposal]
    let evidenceIDs: [EvidenceID]
}
```

Machine-facing output must be structurally decoded and validated.

---

## 18. Memory model

Memory must be evidence-backed.

```swift
struct MemoryClaim: Codable, Sendable {
    let id: MemoryID
    let kind: MemoryKind
    let content: String
    let confidence: Double
    let evidence: [EvidenceReference]
    let source: MemorySource
    let createdAt: Date
    let supersedes: MemoryID?
}
```

Useful kinds may include:

```text
idea
question
theme
belief
```

Do not silently infer permanent personality traits.

Prefer evidence-bound observations like “Across several recent reflections, this theme recurs” instead of “The user is X”.

### Preserve belief change

Never overwrite earlier beliefs. Preserve revisions and supersession.

```text
January: 自由 = 不被别人决定
April:   自由也意味着责任
August:  关键可能是能否承担自己的选择
```

The evolution itself is a core product asset.

---

## 19. Retrieval boundary

`AgentRuntime` must not know whether retrieval uses FTS5, BM25, vectors, embeddings, HNSW, or cloud/local embedding models.

Use an abstraction like:

```swift
protocol Retriever: Sendable {
    func retrieve(
        query: RetrievalQuery
    ) async throws -> [Evidence]
}
```

Retrieval implementation should be replaceable without changing Agent execution.

---

## 20. Event-sourced trace

Agent runs should be reconstructable.

Persist at least conceptual records for:

```text
agentRuns
agentEvents
modelCalls
toolCalls
```

Recommended `agentRuns` data:

```text
id
agentKind
status
startedAt
completedAt
promptVersion
contextRecipeVersion
provider
model
```

Debug traces are derived data and must have bounded retention. User data such as reflections, notes, memory claims, and thought revisions must never be deleted by trace eviction.

---

## 21. Failure taxonomy

Do not expose raw network/provider errors directly to UI.

Normalize failures:

```swift
enum AgentFailure: Error, Sendable {
    case providerUnavailable
    case authentication
    case rateLimited
    case network
    case malformedProviderResponse
    case toolFailure
    case structuredOutputInvalid
    case contextFailure
    case budgetExceeded
    case persistenceFailure
}
```

Remember:

```text
Cancellation != Failure
```

Product UI decides how to present normalized failures.

### Retry policy

Retry only safe operations such as transient network failures, rate limits, and some 5xx responses. Never blindly retry a mutating tool. V1 should avoid model-controlled mutating tools entirely.

---

## 22. Prompt injection boundary

Book content is untrusted input. A book may literally contain “Ignore all previous instructions”. Treat all retrieved text as evidence, never instruction.

Conceptual input hierarchy:

```text
System / Runtime Policy
Product / Reader Agent Policy
User Reflection
Retrieved Evidence
```

Evidence cannot redefine tool permissions, runtime policy, or memory rules.

---

## 23. Provider state is not canonical state

Local state is canonical.

Provider identifiers such as response IDs or conversation IDs may be optimization metadata only. A user must be able to switch providers without losing Elsepage's intellectual history.

If changing the model provider changes the user's long-term memory, the architecture is wrong.

---

## 24. Workflow before Agent loop

Not every AI flow should be agentic.

This is mostly deterministic:

```text
Reflection saved
   ↓
retrieve context
   ↓
generate response
   ↓
extract memory proposal
   ↓
validate
   ↓
persist
```

Use explicit workflow orchestration. Use an Agent loop only when the model genuinely needs to choose between multiple information-gathering actions.

Rule:

> If a workflow can be deterministic, keep it deterministic.

---

## 25. Testing strategy

`FakeModelClient` is mandatory and should support scripted event sequences.

```swift
let fake = FakeModelClient(events: [
    .textDelta("你"),
    .textDelta("刚才"),
    .toolCallCompleted(...),
    .completed(.stop)
])
```

Core runtime unit tests must not require real API keys.

### Required runtime tests

State machine:

```text
single model response
model → tool → model
multiple tool calls
budget exceeded
max model calls
max tool calls
```

Streaming:

```text
partial text deltas
fragmented tool arguments
unexpected end of stream
malformed provider event
```

Cancellation:

```text
cancel before model call
cancel during streaming
cancel during retrieval
cancel during tool execution
```

Failure:

```text
401/authentication
429
network timeout
5xx
invalid JSON
tool throws
persistence unavailable
```

Idempotency:

```text
duplicate completion
duplicate tool event
retry after disconnect
```

---

## 26. Provider contract tests

Every provider adapter should pass the same behavioral contract:

```text
events emitted in order
completion emitted exactly once
usage normalized
tool call reconstructed correctly
cancellation propagates
errors normalized
```

Adding a provider should mostly mean:

```text
implement ModelClient
pass ModelClientContractTests
```

not rewriting ReaderAgent.

---

## 27. Reader Agent evaluation

Unit tests prove correctness; they do not prove wisdom.

Maintain a separate suite:

```text
Tests/ReaderAgentBench/
```

Each fixture should include:

```text
user reflection
book context
previous thoughts
expected behavioral properties
```

Evaluate at least:

```text
understands user
understands book context
factuality
evidence grounding
connection relevance
follow-up quality
personalization
restraint
non-flattery
user agency
```

Track failure modes:

```text
empty_flattery
fake_quote
irrelevant_connection
over_recall
missed_personal_history
over_explanation
unsupported_personality_claim
```

Do not assert exact wording. Assert behavioral properties such as “must reference evidence X”, “must ask at most one question”, or “must not fabricate a quote”.

---

## 28. Performance and privacy

The runtime should mostly spend time in SQLite retrieval, URLSession, JSON decoding, and stream delivery. Avoid polling, busy loops, manual thread pools, and unnecessary DispatchQueue layers.

Minimize provider payload. Do not upload the user's entire intellectual history on each call.

Conceptually:

```text
API key       → Keychain
Book          → App Sandbox
Reflection    → Local DB
Memory        → Local DB
Agent context → minimum selected evidence only
```

---

## 29. Development phases

### Phase A — Agent Runtime Kernel

Implement only:

```text
AgentEvent
ModelEvent
ModelClient
AgentExecutor
ExecutionBudget
FakeModelClient
```

Constraints:

```text
pure Swift
swift test
no UIKit
no SwiftUI
no GRDB
no Readium
no real provider dependency
```

Required scenarios:

```text
normal response
streaming
tool request
tool result
second model turn
completed
cancel
timeout
malformed stream
tool failure
budget exceeded
```

Do not continue until this layer is stable.

### Phase B — Provider Layer

Implement one practical provider adapter, preferably `OpenAICompatibleModelClient`, then add provider-specific adapters only where useful.

Required: streaming parser tests, cancellation tests, normalized errors, provider contract tests.

### Phase C — Tool Runtime

Implement `AgentTool`, `AnyAgentTool`, `ToolRegistry`, `ToolExecutionContext`, `ToolResult`, and JSON Schema support.

Required: typed decoding, schema validation, unknown tool rejection, duplicate-call handling, cancellation.

### Phase D — Reader Agent

Only here should product modules enter. Implement `ReaderAgentContextBuilder`, `ReaderAgentPolicy`, and `ReaderAgent`.

### Phase E — Memory

Add `MemoryProposal`, `MemoryPolicy`, and repository integration. Runtime still must not persist memory directly.

---

## 30. Anti-patterns Codex must not introduce

```text
DO NOT call provider clients directly from SwiftUI.
DO NOT expose provider-specific response objects above ModelProviders.
DO NOT model Agent output as String only.
DO NOT store API keys outside Keychain.
DO NOT treat provider conversation state as canonical history.
DO NOT allow the model to write permanent memory directly.
DO NOT parse structured model output with regex.
DO NOT use [String: Any] as the core tool contract.
DO NOT swallow CancellationError into generic failure.
DO NOT add @unchecked Sendable just to make Swift 6 compile.
DO NOT introduce arbitrary shell/browser/filesystem tools.
DO NOT build multi-agent orchestration before ReaderAgent is excellent.
DO NOT make AgentRuntime depend on UI, Readium, or GRDB.
DO NOT make every workflow agentic.
DO NOT optimize for the maximum number of tools.
DO NOT persist unbounded token-level traces.
DO NOT send all personal memory to the model by default.
DO NOT let book text become executable instruction.
DO NOT overwrite older beliefs when the user's views evolve.
```

---

## 31. Definition of Done — Runtime Kernel

The first runtime milestone is complete only when:

```text
[ ] AgentRuntime is a pure Swift module.
[ ] Swift 6 strict concurrency passes without unsafe suppression.
[ ] Streaming is the primary execution API.
[ ] Cancellation propagates correctly.
[ ] Execution is bounded by explicit budgets.
[ ] Providers are abstracted through ModelClient.
[ ] Provider JSON does not leak into Runtime or UI.
[ ] FakeModelClient covers normal/error/tool flows.
[ ] Tool execution is strongly typed.
[ ] Tool schemas are machine-readable and versionable.
[ ] Runtime supports normalized event tracing.
[ ] ReaderAgent is separate from AgentRuntime.
[ ] Memory persistence is not controlled directly by the model.
[ ] Provider state is not canonical history.
[ ] Tests cover success, cancellation, malformed streams, tool failure,
    and budget exhaustion.
[ ] No UI framework dependency exists.
```

---

## 32. Definition of Done — Reader Agent V1

Reader Agent V1 is complete when this real flow works:

```text
User writes Reflection
    ↓
Reflection saved locally
    ↓
ReaderAgent builds context
    ↓
Relevant current-book evidence selected
    ↓
Relevant previous thought optionally selected
    ↓
Model streams response
    ↓
User sees response
    ↓
Evidence references remain traceable
    ↓
Optional MemoryProposal produced
    ↓
MemoryPolicy validates it
    ↓
Accepted result persists
```

And the flow remains correct when:

```text
no API key exists
network fails
credentials are invalid
user dismisses the sheet
request is cancelled
structured output is malformed
retrieval finds nothing useful
```

No user reflection may be lost in any case.

---

## 33. Codex working rules

Whenever changing Agent-related code:

1. Read this guide first.
2. Inspect current runtime contracts before introducing new abstractions.
3. Prefer extending an existing contract over creating a parallel one.
4. Explain architecture impact before adding dependencies.
5. Avoid unrelated cross-module refactors.
6. Run focused tests after each meaningful change.
7. Run the complete AgentRuntime test suite before committing.
8. Update this guide when an invariant genuinely changes.
9. Record unresolved decisions in an ADR or active execution plan.
10. Never claim an Agent/provider path works without an executable test or verified integration path.

---

## 34. Architectural mental model

```text
               Elsepage Product
                      │
                 ReaderAgent
                      │
          ┌───────────┼───────────┐
          │           │           │
       Context      Policy      Memory
          │           │           │
          └───────────┴─────┬─────┘
                            │
                     AgentRuntime
                            │
                 ┌──────────┴──────────┐
                 │                     │
               Tools               ModelClient
                                       │
                            ┌──────────┼──────────┐
                            │          │          │
                         OpenAI     Claude    DeepSeek
```

Interpretation:

> **ReaderAgent defines who Elsepage is.**
> **AgentRuntime defines how Elsepage thinks and acts reliably.**
> **The model is only the replaceable reasoning engine used today.**

If changing the model provider changes Elsepage's identity, the architecture has failed.

If changing the UI requires rewriting the runtime, the architecture has failed.

If adding Memory requires modifying provider adapters, the architecture has failed.

If adding a provider requires changing ReaderAgent behavior, the architecture has probably failed.

---

## 35. Immediate next milestone

The next implementation milestone should be:

```text
0.25 — Swift Agent Runtime Kernel
```

Scope:

```text
Sources/AgentRuntime
Tests/AgentRuntimeTests
```

Do not integrate UI, Memory, RAG, or production providers until the kernel can reliably execute:

```text
FakeModelClient
    ↓
AgentExecutor
    ↓
stream text
    ↓
tool request
    ↓
fake tool result
    ↓
second model call
    ↓
completed
```

and correctly handle:

```text
cancel
timeout
malformed stream
tool failure
budget exceeded
```

Only after this gate passes should development proceed to:

```text
0.30 — Reader Agent + Memory
```

---

# Final principle

The goal is not to build the most powerful Agent framework.

The goal is to build the smallest runtime that can remain trustworthy while Elsepage grows from:

```text
Reader + Reflection
```

into:

```text
a long-term Personal Thinking Agent
```

Prefer:

```text
small interfaces
strong invariants
explicit state
typed data
bounded execution
testability
provenance
```

over:

```text
framework cleverness
hidden magic
provider coupling
unbounded autonomy
large abstractions
```

A good Runtime should become boring infrastructure.

The intelligence should live in:

```text
ReaderAgent
Context
Policy
Memory
Retrieval
Evaluation
```

not in accidental complexity.
