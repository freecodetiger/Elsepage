# LLM Context Routing — Implementation Record

Status: implemented baseline  
ADR: `docs/adr/0001-llm-context-routing.md`

## Implemented

- New pure Swift `ContextRouting` product.
- Strict Codable routing input and plan contracts.
- Zero-temperature, one-call `LLMReaderContextRouter` with an eight-second and
  500-output-token budget.
- Strict JSON only; Markdown fences and partial/natural-language parsing are
  intentionally rejected.
- `ContextPlanValidator` enforces source availability, Locator requirement,
  query/evidence limits, per-layer character budgets, Reflection response length,
  and no-consecutive-question policy.
- Deterministic fallback on malformed output or model/runtime failure.
- ReaderAgent runs routing before L0/L1/L2 assembly and uses the validated plan to
  include/omit nearby passage, query current-book evidence, select at most one past
  Reflection, bound conversation history, and constrain final response behavior.
- Retrieval still independently enforces current Book and read-so-far.

## Explicitly not implemented

- Memory, Reader Profile, World knowledge or cross-book passage retrieval.
- A separate routing-model configuration UI.
- Model tool calling or direct repository access.
- Persistent routing traces containing user text. Current routing results are
  ephemeral; automated tests provide behavioral observability.
- Structured final-response citations, which remain a separate follow-up.

## Verification contract

- valid strict JSON routes successfully;
- Markdown/invalid output falls back;
- model failure falls back;
- unavailable L1/L2 plans are removed;
- missing Locator prevents book retrieval;
- counts, queries and budgets are clamped;
- a previous Agent question forces `allowQuestion = false`;
- existing reflection persistence and product-loop tests remain green;
- Swift tests and generic iOS build pass.
