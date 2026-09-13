# Thoughts UI Redesign Implementation

## Goal

Implement `docs/THOUGHTS_UI_REDESIGN_SPEC.md` after writing the product decisions
back to the PRD.

## Required sequence

1. Update `ReadLoop_PRD.md` and commit it before application code changes.
2. Add immutable `ReflectionSummary` persistence and migration.
3. Generate summaries after the first Reflection and first AI response.
4. Make first AI response automatic and remove manual reply affordances.
5. Refactor the Thoughts page to a single record stream.
6. Keep glass for navigation/overlays and neutral solid surfaces for cards.
7. Add tests and run the full `swift test` suite.

## Key implementation files

- `ReadLoop_PRD.md`
- `Sources/ReflectionCore/Reflection.swift`
- `Sources/ReflectionCore/ReflectionArchive.swift`
- `Sources/ReaderAgent/ReaderAgent.swift`
- `Sources/Persistence/AppDatabase.swift`
- `Sources/Persistence/ReflectionRepositories.swift`
- `App/Thoughts/ThoughtsView.swift`
- `App/Thoughts/ThoughtsModel.swift`
- `App/Reflection/SessionReflectionSheet.swift`
- `Tests/ReadLoopCoreTests/`
- `Tests/AgentProviderTests/`

## Acceptance

- No primary UI entry for 档案, 有回应, or 请 AI 回应.
- Collapsed cards show only book, Chinese date, and summary.
- Summary is immutable and cascade-deleted with Reflection.
- Missing response/summary is recovered in the background.
- Glass remains on navigation and overlays; cards are neutral solid surfaces.
- `swift test` is green.
