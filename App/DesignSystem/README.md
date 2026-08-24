# Design System

The first semantic tokens and reusable SwiftUI components are compiled from
`App/Library/LibraryView.swift` because the checked-in Xcode project uses an
explicit source-file list, while this workstream is not allowed to edit
`project.yml` or `ReadLoop.xcodeproj`.

When the project is next regenerated, move `ElsepageTheme`,
`ElsepageIconButton`, and `ElsepageBookCover` into this directory without
changing their API. Feature views should continue to consume semantic tokens
instead of introducing raw visual constants.
