# Native System Typography

## Goal

Lock Elsepage App UI typography to Apple system semantic text styles. Remove
custom serif/custom-font UI roles and replace ad-hoc fixed font sizes in
primary SwiftUI surfaces with Dynamic Type styles.

## Scope

- `ReadLoop_PRD.md`
- `docs/UI_LANGUAGE_AND_IA_SPEC.md`
- `App/DesignSystem/ElsepageTheme.swift`
- SwiftUI font declarations in `App/`
- No layout, navigation, persistence, provider, or reader-engine redesign

## Required sequence

1. Record the typography decision in PRD §10.1 and §21 as an accepted
   implementation refinement.
2. Update the locked UI language/IA spec so App UI uses only system semantic
   text styles; cover artwork and EPUB content remain independent.
3. Remove `.serif` roles from `ElsepageTheme.Typography` and all App UI calls.
4. Replace fixed text sizes in `ThoughtsView` with semantic Dynamic Type styles.
5. Preserve system-font sizing for SF Symbols where the size expresses an icon,
   not typography.
6. Run `swift test`, parse changed SwiftUI files, and run `git diff --check`.

## Acceptance

- No `design: .serif` remains in `App/`.
- Primary UI text no longer uses custom typography families or fixed point sizes.
- All App UI text follows Apple semantic text styles and Dynamic Type.
- Reader content/theme behavior is unchanged.
- `swift test` is green; XCTest has no failures.
- Changed App files pass `swiftc -parse`.
