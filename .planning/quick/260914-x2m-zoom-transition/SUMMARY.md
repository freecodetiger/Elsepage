# Transition Shadow Parity Summary

**Status:** Complete  
**Date:** 2026-09-14  
**Branch:** `codex/bookshelf-redesign`

## Delivered

- Restored the visible cover shadow that provides depth.
- Centralized cover size, corner radius and shadow values in
  `ElsepageBookCoverMetrics`.
- Mirrored the same shadow parameters into every `matchedTransitionSource`
  configuration for:
  - current reading cover
  - spine shelf
  - cover shelf
- Reader opening placeholder now uses the same `100 × 150pt` cover geometry
  and shadow.
- Updated the bookshelf spec so real views and transition snapshots must use
  identical clip and shadow parameters.

## Verification

- `swiftc -parse` passed for all changed App files.
- `swift test`: 391 Swift Testing tests passed; XCTest suites passed.
- `git diff --check` passed.
- `Package.resolved` was restored after the test run.
- Xcode build and real-device open/return animation review remain with the user.
