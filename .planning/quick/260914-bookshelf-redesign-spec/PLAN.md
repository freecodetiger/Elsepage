# Bookshelf Redesign Spec

## Goal

Write the authoritative UI spec for the physical-feeling bookshelf redesign,
based on the confirmed decisions:

1. Current-reading desk above a physical shelf.
2. Mixed cover/spine presentation.
3. Medium physical interaction: lift, pull-out, snap and haptics.
4. Metadata density only on the current-reading book.
5. Neutral shell with semantic and cover-derived color; remove the forced
   black-and-white constraint.

## Deliverables

- `docs/BOOKSHELF_REDESIGN_SPEC.md`
- Update `docs/UI_LANGUAGE_AND_IA_SPEC.md` to remove the monochrome hard rule.
- Update `ReadLoop_PRD.md` §10.1 to describe semantic minimal color rather than
  black-and-white-only chrome.

## Non-goals

- No persistence or Reader-engine changes.
- No tilt/parallax/gyroscope interaction.
- No literal wood texture.
- No forced reorder or arbitrary drag-and-drop in the first version.
