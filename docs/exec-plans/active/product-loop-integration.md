# Elsepage Product Loop Integration

Status: implemented; device UX verification pending  
Source of truth: `ReadLoop_PRD.md`, `ReadLoop_Technical_Design.md`, and
`docs/ELSEPAGE_SWIFT_AGENT_RUNTIME_GUIDE.md`

## Current journey audit

Before this pass the implemented journey was fragmented:

```text
Today ──> Library ──> Reader ──> Library
                              (no explicit session ending)

Today ──> standalone Reflection sheet ──> dismiss

Thoughts ──> request first Agent reply
         └─> no source navigation / no continuation
```

- Today derived some state from repositories, but “continue reading” only opened
  Library instead of the current book.
- Reader created a session after its first Locator callback, but exposed no
  “读到这里” action and did not end a session on the normal product path.
- Session annotation counts were whole-book totals rather than changes made in
  the session.
- Every ended session was considered reflection-worthy, including accidental
  opens.
- Reflection correctly persisted user text first, but immediately dismissed;
  Agent feedback was a separate manual action in Thoughts.
- ReaderAgent received only the Reflection text. It had no session/book evidence,
  previous conversation, or previous-thought retrieval.
- Thoughts displayed persisted Reflection data, but only the last Agent response;
  it could not open the source Locator and did not support continued discussion.
- App-level navigation state did not connect Today or Thoughts to Reader.
- Cancellation was generally normalized, but dismissing the Reflection surface
  also removed all visible progress for an in-flight optional Agent response.

## Target journey

```text
Today (repository-derived state)
  └─> current Book at saved Locator
        └─> “读到这里”
              └─> meaningful-session policy
                    ├─> too short: return quietly
                    └─> Reflection sheet
                          └─> persist user text first
                                ├─> no Provider: local completion
                                └─> ReaderAgent streams a concise response
                                      └─> optional continued discussion
                                            └─> Thoughts archive
                                                  └─> exact evidence Locator
                                                        └─> Reader
```

## State ownership

- Books, positions, sessions, reflections, evidence and messages remain
  repository-backed source-of-truth state.
- Reader owns high-frequency Locator, chrome, selection and annotation snapshots.
- Session lifecycle remains serialized by `ReadingSessionService`.
- The Reflection surface owns only its draft and current presentation state; it
  reloads persisted conversation after every completed write.
- AppShell owns only cross-feature navigation intent (selected tab and an optional
  Reader destination). It does not copy domain records into a global ViewModel.
- ReaderAgent owns product context assembly and optional model execution. Provider
  details remain behind `ModelClientFactory`.

## Meaningful session policy

Offer Reflection when an explicitly ended session satisfies at least one rule:

- wall-clock duration is at least 3 minutes; or
- reliable total progression advanced by at least 0.5%; or
- the user created at least one Highlight or Note during the session.

This deterministic policy avoids prompting after accidental opens. Backgrounding
flushes reading state but does not fabricate a session ending.

## Completion criteria

- [x] Today opens the actual current book and is derived from repository state.
- [x] Reader explicitly and idempotently ends a real ReadingSession.
- [x] Session counts only annotations created during that session.
- [x] Short accidental opens do not prompt Reflection.
- [x] Reflection is persisted before any Provider request.
- [x] Agent streaming remains in the Reflection experience.
- [x] A user can continue the same Reflection conversation.
- [x] Thoughts shows persisted user content and conversation.
- [x] Thoughts can open exact Locator evidence in Reader.
- [x] One deterministic, evidence-backed previous-thought reconnect path works.
- [x] No Provider is required for Read → Reflect → Preserve → Reopen.
- [x] Cancellation and Provider failure preserve the Reflection.
- [x] Product-flow integration tests pass.
- [x] Available Swift and unsigned iOS builds pass.

## Implemented result

- `TodayProductStateResolver` is the single deterministic state machine used by
  Today and product-flow tests.
- Reader starts or reuses one unfinished Session and exposes “读到这里”. Session
  ending is idempotent; annotation counts are computed from creation time relative
  to the Session start instead of whole-book totals.
- Reflection uses one surface for local save, optional streaming response, one
  related past thought, and optional continued discussion. The save callback fires
  before ReaderAgent begins.
- User continuation messages use stable IDs and idempotent repository writes.
- `reflectionConnections` migration v6 stores at most one conservative lexical
  reconnect selected by ReaderAgent, with both Reflection IDs and relevance.
- Thoughts projects real messages, exact Locator evidence, and persisted
  connections; either source can reopen Reader at its full Readium Locator JSON.
- Readium selection now offers “聊聊这句”, which opens the same user-first
  Reflection surface with the selected passage as evidence. No automatic AI
  explanation occurs.
- Automated verification: 68 Swift tests passed; Generic iOS unsigned build
  succeeded with Swift 6 strict concurrency. The iPhone 17 Pro / iOS 26.5
  simulator also passed 53 hosted core tests and 2 real Readium EPUB integration
  tests.

## Explicitly deferred

- Voice/ASR, embeddings, generalized Memory proposals, Reader Profile, knowledge
  graph, habit/gamification, background autonomous work, and additional formats.

## Unresolved verification risks

- Native Readium selection, presentation stacking, and exact Locator return must
  be exercised on a simulator or physical iPhone; compilation alone is not UX
  verification.
- Wall-clock duration is currently honest elapsed time, not foreground-only active
  reading time. Backgrounding does not end the session, but a long background gap
  can make the duration threshold pass. Active-duration accounting remains a
  follow-up if device testing shows false prompts.
- The full manual flow (including keyboard, sheet dismissal, Reader return and
  physical-device selection menu ordering) has not been claimed as verified.
- Reflection retrieval is deliberately conservative lexical matching over the 50
  most recent entries. It is suitable for Reconnect V0, not a replacement for the
  later FTS5/book indexing and evaluated retrieval pipeline.
