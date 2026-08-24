# Reader Foundation — Full Xcode Verification Gate

Reader Foundation is not release-ready until this checklist passes with a full Xcode installation, installed iOS platform, and simulator runtime. Portable `swift test` results do not satisfy this gate.

## Build prerequisites

- Select the full Xcode developer directory with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- Run `xcodegen generate` and confirm the generated project has no uncommitted differences.
- Resolve Swift packages without changing the pinned GRDB 7.11.1 or Readium 3.3.0 versions.
- Run `xcodebuild -project ReadLoop.xcodeproj -scheme ReadLoop -destination 'platform=iOS Simulator,name=iPhone 16' build test` (adjust only the installed simulator name).
- Confirm `ReadiumPublicationIntegrationTests` opens the bundled CC0 EPUB and extracts its metadata.

## Simulator and device behavior

- Launch on at least one current iPhone simulator and one physical iPhone.
- Import `minimal.epub` through Files and import a representative, legally owned reflowable EPUB.
- Confirm corrupt, unsupported, and DRM-protected files produce an error and no Library entry or permanent EPUB.
- Open an imported EPUB, page forward and backward, use chapter navigation, and confirm layout remains readable.
- Terminate and relaunch the app; confirm the exact last Readium Locator is restored.
- Select text and verify the 高亮 and 批注 actions appear and complete successfully.
- Create a note and verify its original selected-text Locator remains navigable.
- Reopen the publication and verify every persisted highlight is rendered in the expected color.
- Navigate from a persisted highlight back to its Locator.
- Rotate while reading and verify the current location does not jump unexpectedly.
- Background and foreground during reading; verify the embedded HTTP server resumes and the publication remains readable.
- Force-quit immediately after a location change, highlight, and note save; verify durable recovery.

## Highlight restoration integration point

Portable code now produces `[HighlightDecoration]` through `HighlightRestorationService`. The intentionally unimplemented iOS step belongs immediately after `EPUBNavigatorViewController` creation in `ReadiumReaderView.Coordinator.open(in:)`:

1. Load the restoration plan for the current `BookID`.
2. Recreate each Readium `Locator` from the decoration's exact JSON.
3. Map its color to `Decoration.Style.highlight(tint:isActive:)`.
4. Call `navigator.apply(decorations: readiumDecorations, in: "highlights")`.
5. Confirm `navigator.supports(decorationStyle: .highlight)` before enabling the feature.

Do not mark this item complete from code inspection alone. It requires successful iOS compilation plus visible rendering and reopen tests.

## Gate result

Record the Xcode version, iOS SDK, simulator/device, commands, test result, and any Readium warnings in the release checklist. Reader Foundation stays blocked while any item above is unverified.
