# Bookshelf First Pass Summary

**Status:** Complete  
**Date:** 2026-09-14  
**Branch:** `codex/bookshelf-redesign`

## Delivered

- Added a current-reading desk above the library.
- The desk uses the full cover, title, author, progress, bookmark color and
  last-opened date.
- A pending Reflection is now represented as a note attached to the current
  book and opens the existing reflection sheet.
- Added a physical shelf view with generated colored spines:
  - vertical Chinese title
  - stable fallback color
  - progress mark
  - press lift
  - pull-out animation
  - `bookPulled` haptic
- Added a toolbar toggle between spine and cover display modes.
- Kept the cover grid as a second mode and as the accessibility fallback.
- Added stable current-book resolution through `LibraryModel.currentBook`.
- Moved reading/thinking streak display to My Mind.
- Removed the old Today tab and `TodayView`.

## Verification

- `swift test`: 391 Swift Testing tests passed; XCTest suites passed.
- `swiftc -parse` passed for changed App files.
- `git diff --check` passed.
- The Xcode project was regenerated with XcodeGen.
- No persistence migration or reader-engine change.
