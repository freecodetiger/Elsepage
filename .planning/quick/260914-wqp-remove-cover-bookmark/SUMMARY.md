# Remove Cover Bookmark Summary

**Status:** Complete  
**Date:** 2026-09-14  
**Branch:** `codex/bookshelf-redesign`

## Delivered

- Removed the thin colored progress Capsule from the current-reading cover.
- Kept progress in the fixed metadata slot through the progress bar and percent.
- Kept the cover as a pure book object with no badge, bookmark or decoration.
- Removed stale bookmark/note language from the bookshelf spec.
- Unified the spec around “补写想法” and “继续阅读” as same-level actions.

## Verification

- `swiftc -parse` passed for the changed App file.
- `swift test`: 391 Swift Testing tests passed; XCTest suites passed.
- `git diff --check` passed.
- `Package.resolved` was restored after the test run.
- Final visual confirmation on device remains with the user.
