# UI Language and Information Architecture Refresh

## Goal

Make the primary product experience Chinese-community friendly, establish a
neutral black/white visual language, and reduce the density of the 想法/我的
surfaces without rewriting the underlying domain or persistence models.

## Locked decisions

- User-facing brand: 页外. Internal ReadLoop/Elsepage names stay out of primary UI.
- Primary tabs: 今天 / 书架 / 想法 / 我的.
- Main flows use natural Chinese. Advanced settings keep technical terms such as
  Embedding, Reranker, Provider, API Key and Base URL.
- App chrome uses neutral black/white tokens. Reader paper/sepia/dark themes stay
  independent and continue to prioritize reading comfort.
- Existing Reflection, Thought, Question and Memory data models remain intact.

## Tasks

1. Write `docs/UI_LANGUAGE_AND_IA_SPEC.md` and update PRD §10.1 before visual
   implementation. Lock brand, tabs, object names, page hierarchy and token roles.
2. Split palette semantics into background/surface/border, brand, interactive,
   success/warning/danger and on-colors. Update `ElsepageTheme` aliases and the
   accessibility contrast tests.
3. Replace primary-flow English terminology and inconsistent brand names while
   preserving technical wording in advanced settings.
4. Refactor 想法 from three equal modes (时间/书籍/日志) into a clear primary
   content axis plus secondary grouping. Reduce collapsed and expanded card density.
5. Refactor 我的 into a simpler hierarchy: 正在形成的看法 / 还在想的问题 /
   AI 记住的我 / 成就. Reduce redundant metadata and move evidence/actions behind
   explicit expansion.
6. Run `swift test`, restore `Package.resolved` if testing rewrites it, inspect the
   final diff, and write the quick-task summary.

## Verification

- `swift test` fully green.
- No user-facing ReadLoop/ElsePage/Reflection/Agent leakage in primary flows.
- Primary palette has neutral background/surface/border and separate status roles.
- 想法 and 我的 have one obvious primary reading order and details on demand.
- Git diff contains no persistence migration or reader-engine rewrite.
