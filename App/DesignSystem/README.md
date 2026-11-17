# Design System

This directory owns the app's domain-independent semantic tokens and reusable
SwiftUI components. Feature views consume these tokens instead of introducing
repeated raw visual constants.

## Start here

- `ElsepageDesignTokens.swift` — semantic colors, type, spacing, radius,
  border/elevation, motion, and control states.
- `ElsepageDesignComponents.swift` — Button, Icon Button, List Row, Section
  Header, Input, Card, Empty/Loading/Error, Banner/Toast.
- `ComponentCatalogView.swift` — DEBUG-only catalog with Light, Dark, and
  Accessibility XL previews.
- `ElsepageTheme.swift` and `ElsepageComponents.swift` — the legacy tokens and
  components still used by existing screens. They remain compatible; migrate
  one surface at a time.

## Rules

- Prefer system `NavigationStack`, `TabView`, `Sheet`, `Button`, `TextField`,
  `List`, and `ContentUnavailableView`. Do not reimplement them.
- Use semantic colors and `Font.TextStyle` only. No fixed font sizes or raw RGB
  values in feature views.
- Keep rows transparent; cards belong to grouped containers, not every row.
- Respect Reduce Motion through `ElsepageMotion` helpers.
- New UI should use the new tokens/components. Existing pages migrate per
  `docs/design/04-migration-guidelines.md`.

## Tests

`Tests/DesignSystemTests` contains token tests and `ImageRenderer` snapshots
(Light/Dark). See `docs/design/04-design-system-guide.md` for the record-mode
flow.
