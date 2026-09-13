# Thoughts UI Redesign Spec

## Goal

Write the authoritative spec for the redesigned 想法 page and its supporting
summary pipeline. The spec must align with the interactive HTML prototype while
preserving the app's existing glass material for navigation and overlays.

## Locked product decisions

- Every Reflection automatically receives an AI response. Remove all manual
  "请 AI 回复" affordances.
- The 想法 page has no 档案 entry, no archive filter, and no "有回应" status.
- Collapsed cards show only book, Chinese date, and the generated summary.
- Relations and discussion counts appear only after expansion.
- Summary is generated after the first Reflection and its first AI response,
  then persisted and never modified.
- Glass is reserved for navigation, tab bar, menus, sheets, and floating
  overlays. Content cards and long-form reading surfaces use neutral solid
  surfaces.
- UI language remains Chinese-first; dates always render in Chinese.

## Deliverable

- `docs/THOUGHTS_UI_REDESIGN_SPEC.md`
- Update `docs/UI_LANGUAGE_AND_IA_SPEC.md` so the older Thoughts page section
  points to the new authoritative spec instead of retaining conflicting rules.

## Verification

- No conflicting definitions remain for archive, response status, or filters.
- Summary lifecycle, fallback behavior, persistence invariants, and UI
  acceptance are explicit.
- Glass boundaries, typography, card hierarchy, and Chinese date formatting are
  explicit.
