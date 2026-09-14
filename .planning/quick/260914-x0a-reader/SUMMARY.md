# Reader Return Transition Summary

**Status:** Complete  
**Date:** 2026-09-14  
**Branch:** `codex/bookshelf-redesign`

## Root Cause

The matched transition source used a `100 × 150pt` cover, but
`ElsepageBookCover` rendered its shadow outside those bounds. The zoom snapshot
therefore did not match the actual source view, so the returned shelf cover
could appear to change size and then gain its shadow after the transition.

The Reader loading placeholder also used a different `156 × 234pt` cover,
making the two ends of the transition less consistent.

## Fix

- Added a default-preserving `showsShadow` option to `ElsepageBookCover`.
- Disabled the shadow for the desk cover and Reader placeholder.
- Introduced shared `ElsepageBookCoverMetrics` for the exact `100 × 150pt`
  transition geometry.
- Used the same cover frame at the source, shelf book and Reader placeholder.
- Clipped the matched transition source to the same rounded rectangle as the
  visible cover.
- Documented the no-size-change/no-delayed-shadow acceptance rule.

## Verification

- `swiftc -parse` passed for all changed App files.
- `swift test`: 391 Swift Testing tests passed; XCTest suites passed.
- `git diff --check` passed.
- `Package.resolved` was restored after the test run.
- No automated package-level test can exercise the SwiftUI zoom rendering;
  Xcode build and real-device return-animation verification remain with the user.
