# Fixed Reading Desk Summary

**Status:** Complete  
**Date:** 2026-09-14  
**Branch:** `codex/bookshelf-redesign`

## Delivered

- Replaced content-driven desk sizing with a fixed horizontal candidate on
  regular sizes.
- Kept the horizontal/vertical desk decision dependent on available width and
  Dynamic Type, never on title or author length.
- Reserved a fixed two-line title slot with tail truncation.
- Reserved fixed single-line slots for author, progress/date and actions.
- Made the two regular-size actions equal width.
- Kept the second action slot reserved when no Reflection is pending, so the
  position of “继续阅读” does not move between books.
- Preserved the fixed `140 × 182` book stage and `100 × 150` cover frame.
- Updated the bookshelf spec and acceptance criteria.

## Verification

- `swiftc -parse` passed for all changed App files.
- `swift test`: 391 Swift Testing tests passed; XCTest suites passed.
- `git diff --check` passed.
- `Package.resolved` was restored after the test run.
- Final visual confirmation on device remains with the user.
