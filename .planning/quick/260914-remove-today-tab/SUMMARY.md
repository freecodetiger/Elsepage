# Remove Today Tab Summary

**Status:** Complete  
**Date:** 2026-09-14

## Delivered

- Updated PRD and UI language/IA spec from four tabs to three:
  - 书架
  - 想法
  - 我的
- Removed `TodayView` and the `今天` tab.
- App now opens on 书架.
- Preserved the only unique Today capability as `LibraryNextActionModel/View`:
  - pending Reflection prompt
  - explicit “今天先不了” dismissal
  - existing reflection sheet flow
- The Next Action card appears above the Library grid only when a pending
  Reflection exists.
- If there is no next action, the Library stays a clean book grid.
- Reading and thinking streak derivation moved into `MyMindModel`.
- Streak badges now appear in the top “阅读与思考” section of 我的.
- Updated Xcode project membership.

## Verification

- `swift test`: 391 Swift Testing tests passed; XCTest suites passed.
- `swiftc -parse` passed for changed App files.
- `git diff --check` passed.
- No `TodayView`, `.today`, or user-facing `今天` tab reference remains in App.
