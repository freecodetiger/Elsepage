# ADR 0001: LLM-planned, locally enforced Reader context routing

Status: accepted  
Date: 2026-08-25

## Context

The runtime guide originally recommended a deterministic context builder and
model-driven routing only when that proved insufficient. The product now needs
semantic decisions that lexical rules handle poorly: distinguishing an emotional
record from a conceptual question, deciding when nearby text is enough, and
recognizing when a past thought would materially deepen the response.

Giving a model repository or retrieval access would violate local-first boundaries,
make read-so-far spoiler protection probabilistic, and couple ReaderAgent to data
implementation details.

## Decision

Use an LLM to propose one strict `ReaderContextPlan`. Swift then validates and
executes it.

```text
LLM decides what may be useful
Swift decides what is allowed
RetrievalCore decides what is relevant
Persistence decides how it is loaded
```

The router receives only the current Reflection, a bounded conversation preview,
lightweight reading metadata, and source-availability flags. It cannot execute
tools or data access. Its JSON plan may request at most one current-book retrieval
and one past-thought retrieval.

`ContextPlanValidator` owns the hard policy:

- current Book only;
- a known Locator is required for book retrieval;
- RetrievalCore/SQL always enforce read-so-far;
- only currently enabled L0/L1/L2 sources are accepted;
- query length, evidence count and character budgets are clamped;
- a prior Agent question forces the current turn to respond and stop;
- Memory, Profile, World and external sources are unavailable in this phase.

Non-JSON output, Markdown-wrapped JSON, timeout, cancellation, or model failure
uses a deterministic minimal fallback. Router rationale is ephemeral and is not
user Source of Truth.

## Consequences

- A normal Agent response may require two sequential calls to the configured
  BYOK model: one small zero-temperature routing call and one response call.
- Routing failure does not prevent the response call or mutate Reflection data.
- Provider cost and latency increase slightly; routing uses an eight-second,
  500-output-token hard budget.
- Router quality becomes testable independently from retrieval and response style.
- AgentRuntime remains product-agnostic and has no RetrievalCore dependency.

## Rejected alternatives

- Pure keyword routing: deterministic but weak for tone and latent intent.
- Letting ReaderAgent directly call retrieval tools: weakens module boundaries and
  makes safety dependent on model behavior.
- Asking the response model to retrieve and answer in one unstructured call:
  prevents strict validation, provenance and predictable fallback.
