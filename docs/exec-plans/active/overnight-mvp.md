# Elsepage MVP Overnight Execution Plan

## Current baseline (2026-08-25)

- Integration branch: `develop`, currently at `aedba2f` plus a small uncommitted
  AppShell/cancellation hygiene change that is verified by `swift test` (38 tests).
- Reader Foundation already has Readium EPUB import/opening, stable book identity,
  GRDB migrations v1–v4, position persistence, highlights, notes, reader
  preferences, search and a UIKit navigator bridge.
- `ReadingSessionCore`, `ReflectionCore`, their repositories and provenance
  schema exist, but no app flow currently creates a session or reflection.
- Today and Thoughts are placeholders. There is no provider configuration,
  Keychain integration, model client, Agent runtime, thought archive, or
  reconnection.
- Portable Swift verification is available. Device-level Readium behavior remains
  a manual Xcode gate; it must not be claimed as verified here.

## Target MVP

The integrated app must let a fresh user import/read an EPUB, end a meaningful
reading session, save a text reflection locally before any network work, see it
in Thoughts, and optionally receive a concise BYOK response. Today must surface
the next appropriate action. Reading stays fully usable with no provider.

## Architecture invariants

1. EPUB, reading state, raw reflection and evidence are local source data.
2. Raw user reflection is saved before an Agent/model request and is never
   overwritten by derived content.
3. API secrets live only in Keychain; SQLite stores non-secret configuration.
4. Readium remains the EPUB engine and Reader domain remains UIKit/SwiftUI-free
   outside its narrow bridge.
5. Providers stay behind a small `ModelClient` contract; no backend, Node/Pi,
   MCP, browser, shell, or general-purpose tools.
6. Evidence/provenance is explicit; derived memory cannot become unsupported
   user identity.
7. Existing migrations are append-only. Coordinator owns final numbering/order.

## Contracts frozen before parallel work

- `ReadingSession`, `ReadingSessionRepository`, `Reflection`,
  `ReflectionRepository`, `BookLocator`, and existing v1–v4 schema are the
  starting contracts. Workers propose additive changes only.
- `AppModel`, `AppShell`, `project.yml`, final migration ordering and all
  cross-feature dependency injection are coordinator-owned.
- Agent integration consumes persisted `Reflection` and may only write a
  separately authored derived `ReflectionMessage` after the raw reflection save.

## Dependency graph and ownership

```text
Reader hardening ──────────┐
                            ├── coordinator wiring / MVP verification
Reflection product loop ───┤
Agent + BYOK ──────────────┤
Thoughts + local memory ───┘
```

| Track | Owns | Does not own |
| --- | --- | --- |
| A Reader hardening | Reader/Library feature code, reader tests, gate doc | AppModel/AppShell/project.yml/schema order |
| B Reflection loop | Session/reflection feature services/views, domain tests | top-level tabs, provider code, migration order |
| C Agent/BYOK | Agent/ModelProvider/Keychain modules and unit tests | AppModel/AppShell/project.yml, raw reflection schema semantics |
| D Thoughts/memory | Thought domain/persistence proposal and Thoughts feature | provider code, top-level tabs, migration order |
| Coordinator | baseline, shared wiring, migrations, integration, full tests/build/docs | opportunistic feature refactors |

## Integration order

1. Reader hardening: protect Reader reliability before hooking in the loop.
2. Reflection loop: expose the local-first core product action.
3. Agent/BYOK: add optional response without making reflection dependent on it.
4. Thoughts/memory: show source material and a restrained local reconnection.
5. Coordinator resolves schema/wiring conflicts and runs the strongest available
   test/build gates after every merge.

## Verification gates

- Each worker runs targeted `swift test` and records the exact command/result.
- Coordinator runs full `swift test`, `xcodegen generate`, and unsigned iOS build.
- Device/simulator Readium checks follow `docs/READER_FOUNDATION_XCODE_GATE.md`;
  the final handoff distinguishes automated evidence from manual verification.
- Disk space is checked before/after work. Only reproducible caches may be
  removed if necessary.

## Known risks / unresolved decisions

- Current deployment target is iOS 18 despite the technical recommendation; do
  not change it during this run without a specific API need.
- The Readium bridge remains in the App layer, a documented short-term boundary
  deviation from the Technical Design.
- The existing gate document has stale wording about highlight restoration and
  must be corrected by Reader hardening.
- Existing `ReadingSession` duration is wall-clock based. Product UI must label
  it honestly and avoid implying precise active-reading time.
- The core package targets are portable; UIKit/Keychain UI implementation needs
  an iOS compile gate before it can be called device-verified.

## Morning handoff checklist

- Record worktree branches/commits, merge order, schema additions, tests/builds,
  unresolved integration issues and manual-device checks in this document.
- Update stale README/gate documentation if implementation materially changes it.

## Track B handoff — reflection loop

- Branch: `codex/overnight-reflection`.
- Adds `ReadingSessionService` as the serialized, idempotent lifecycle owner for
  a book's unfinished session, plus `SessionEndingSummary` for honest
  wall-clock/progress presentation.
- Adds `TextReflectionSubmissionService` and a stable `TextReflectionDraft`.
  A retry with the same draft ID returns the existing raw Reflection; a
  conflicting retry is rejected. The raw text and locator/session evidence are
  committed by the existing transactional Reflection repository before any
  downstream action (there is no Agent call in this track).
- Adds `App/Reflection/SessionReflectionSheet.swift`: a native text-only sheet
  with an explicit safe skip action. It is deliberately not yet top-level wired.
- Coordinator integration: construct `GRDBReadingSessionRepository` and
  `GRDBReflectionRepository` beside the existing repositories in `AppModel`;
  inject them into the feature that constructs `ReaderModel`. On reader open,
  call `ReadingSessionService.start(bookID:at:)` once a current locator exists.
  On the explicit “end reading” reader control, flush the current locator,
  call `end(id:at:highlightCount:noteCount:)`, then present
  `SessionReflectionSheet` with the resulting summary and current locator.
  Do not end a session merely because SwiftUI dismisses a view.
- No migration is required: the existing v3/v4 tables and repository contracts
  cover this flow.
- Verification: `swift test --filter ReflectionLoopServiceTests` was started;
  on this shared host it is waiting for SwiftPM dependency resolution/cache
  locks from parallel worktrees. Run it (and then full `swift test`) once the
  shared resolver is free.
