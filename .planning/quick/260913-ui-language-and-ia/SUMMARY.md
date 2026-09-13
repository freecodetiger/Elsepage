# UI Language and Information Architecture Refresh Summary

**Status:** Complete (code/package side)  
**Branch:** `codex/ui-language-and-ia`  
**Date:** 2026-09-13

## Delivered

- Added `docs/UI_LANGUAGE_AND_IA_SPEC.md`, locking:
  - user-facing brand: 页外
  - tabs: 今天 / 书架 / 想法 / 我的
  - objects: 阅读记录 / 看法 / 问题 / 记忆 / 阅读档案
  - primary-flow Chinese language and advanced-settings exceptions
  - black/white token roles and page hierarchy
- Updated PRD §10.1 and added §21.9 to record the transition from warm sage
  editorial styling to neutral black/white app chrome.
- Split `ElsepagePalette` into background/surface/border, content, brand,
  interactive, on-interactive, success/warning/danger and reader-sepia roles.
- Added accessibility coverage for:
  - primary/secondary/tertiary and interactive text contrast
  - on-interactive button labels
  - success/warning/danger contrast
  - neutral chrome tokens staying monochrome in light and dark modes
- Replaced primary-flow engineering terms and inconsistent brand names while
  keeping technical terms in advanced settings.
- Refactored 想法:
  - primary axis is now 记录 / 档案
  - time vs book is a secondary grouping menu
  - collapsed cards prioritize the user's original text
  - statuses are capped
  - AI response and conversation are primary; context/evidence is disclosed
  - archive reading context and citations live under 更多阅读脉络
- Refactored 我的:
  - order is 正在形成的看法 / 还在想的问题 / AI 记住的我 / 成就
  - achievements moved to the bottom
  - each content section previews at most three items with explicit expansion
  - retired memories are disclosed separately
  - memory actions and evidence appear only after expansion
  - UI section titles use system sans-serif typography
- Switched app-shell cards and controls from glass/green styling to solid neutral
  surfaces with hairline borders. Reader themes remain independent.

## Verification

- `swift test`: green.
- Swift Testing report: 388 tests in 15 suites passed.
- XCTest suites: 0 failures.
- `swiftc -parse` passed for all changed App view files.
- `git diff --check` passed.
- No persistence migration or reader-engine change was introduced.

## Pending User Acceptance

- Xcode build and real-device visual QA are still owned by the user.
- Confirm light/dark rendering across 今天 / 书架 / 想法 / 我的 / Reader Help.
- Confirm 想法 grouping and disclosure ergonomics on a real device.
- Confirm 我的 memory expansion, retired-memory disclosure and action density.
