# Native System Typography Summary

**Status:** Complete (package side)  
**Date:** 2026-09-14  
**Branch:** `codex/ui-language-and-ia`

## Delivered

- Updated `ReadLoop_PRD.md` before code changes:
  - App UI uses Apple system semantic typography only.
  - Chinese uses the system PingFang SC fallback; Latin/numerals use SF Pro.
  - App chrome cannot hard-code third-party, Songti, or custom serif typefaces.
  - Reader content and publisher cover artwork remain independent.
- Added PRD §21.11 recording the accepted typography refinement.
- Updated `docs/UI_LANGUAGE_AND_IA_SPEC.md` §9 and its acceptance rules.
- Updated `ElsepageTheme.Typography` to system semantic styles.
- Removed every `.serif` design role from the App target:
  - Onboarding
  - Reflection header and quoted passage
  - Reader chrome
  - Reader Help
  - Note editor
  - Thoughts list/detail
- Replaced ad-hoc fixed text sizes in `ThoughtsView` with Dynamic Type styles:
  - `.headline`
  - `.title3`
  - `.subheadline`
  - `.footnote`
  - `.caption`
- Kept `.font(.system(size:))` only for SF Symbol icon geometry where the value
  is a drawing size, not a typography role.
- Restored `Package.resolved` after `swift test` rewrote it.

## Verification

- `swift test`: 391 Swift Testing tests passed; XCTest suites passed.
- `swiftc -parse`: all changed App files passed.
- `git diff --check`: passed.
- Source audit: no `design: .serif` or `Font.custom` remains in `App/`.
- No Xcode build, simulator, or real-device visual acceptance was run by the agent.

## Pending User Acceptance

- Xcode build and device check for system Chinese/Latin font fallback.
- Verify Dynamic Type at accessibility sizes across Onboarding, Thoughts,
  Reader Help, Note editor, and Reflection.
