# Wood Rollback Summary

**Status:** Complete  
**Date:** 2026-09-14  
**Branch:** `codex/bookshelf-redesign`

## Delivered

- Reverted the procedural wood desk and wooden shelf boards.
- Restored the low-noise neutral bookshelf treatment.
- Removed the desk’s separate placeholder surface.
- Removed the book page-edge layer, base plate and extra outer shadow from the
  current-reading cover.
- The desk book now uses exactly the same `100 × 150pt` cover frame as the
  transition source and shelf representation.
- Preserved fixed desk geometry, metadata slots, action parity, bookmark
  removal, zoom transition and Reduce Motion behavior.
- Recorded the material rollback decision in the PRD and bookshelf spec.

## Verification

- `swiftc -parse` passed for all changed App files.
- `swift test`: 391 Swift Testing tests passed; XCTest suites passed.
- `git diff --check` passed.
- `Package.resolved` was restored after the test run.
- Xcode build and real-device visual review remain with the user.
