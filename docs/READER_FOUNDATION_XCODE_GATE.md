# Reader Foundation — Full Xcode Verification Gate

Reader Foundation is not release-ready until this checklist passes with a full Xcode installation, installed iOS platform, and simulator runtime. Portable `swift test` results do not satisfy this gate.

## Current implementation status (2026-08-28)

The Reader Experience pass (annotation interaction v2, rebuilt in place) is code-complete and has passed portable Swift tests and an iOS simulator build. It has **not** been manually exercised on a physical iPhone.

Verified environment:

- Xcode 17 / iOS 26.5 SDK;
- `swift test`: 215 tests passed (including 12 new `AnnotationMenuPlacerTests`);
- `xcodebuild -project ReadLoop.xcodeproj -scheme ReadLoop -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build`: succeeded.
- Xcode test host and direct GRDB test dependency are explicitly generated from `project.yml`.

The hosted simulator integration target currently logs duplicate Objective-C class warnings for Swift package modules linked into both the host app and test bundle. Tests pass, and the warning is confined to the hosted test process, but the package/linkage layout should be revisited if it causes casting failures or test instability. It must not be mistaken for physical-device Reader verification.

Implemented and covered where deterministic:

- lossless Readium Locator persistence with stale-write prevention;
- cancellation separated from user-visible open/persistence failures;
- preferences submitted to the existing Navigator without Publication recreation;
- paginated and vertical-scroll modes;
- bounded, deduplicated return history for TOC/search/annotation jumps;
- persisted highlight decoration restoration and duplicate-anchor prevention;
- one-tap selection highlighting via the custom in-place selection toolbar (system edit menu suppressed, Readium `Selection.frame` anchoring — annotation interaction v2, see `docs/READER_EXPERIENCE_OPTIMIZATION_PLAN.md`);
- live-saving note editor sheet, including adding a note to an existing highlight;
- deletion semantics that preserve Note content (note unlink persisted; one-tap undo while the notice pill is visible);
- debounced/cancellable search with stale-result rejection;
- content-first chrome that hides after reading movement and ignores taps while text is selected.

The following remain device verification gates rather than claims:

- selection handles and custom editing actions in Chinese, English, mixed text, and near screen edges;
- visual highlight tint and interaction in every theme;
- exact position across background/foreground, rotation, force quit, and relaunch;
- WKWebView behavior when switching scroll mode and typography during an open publication;
- note sheet keyboard, backgrounding, and interactive-dismiss behavior;
- TOC/search/highlight jumps and return history against representative books;
- VoiceOver, Dynamic Type around Reader chrome, and landscape layout.

## Build prerequisites

- Select the full Xcode developer directory with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- Run `xcodegen generate` and confirm `ReadLoop.xcodeproj` is reproducible from `project.yml` (apart from expected package-resolution state).
- Resolve Swift packages without changing the pinned GRDB 7.11.1 or Readium 3.3.0 versions.
- Run `xcodebuild -project ReadLoop.xcodeproj -scheme ReadLoop -destination 'platform=iOS Simulator,name=iPhone 16' build test` (adjust only the installed simulator name), then run an unsigned generic-device build if signing is unavailable.
- Confirm `ReadiumPublicationIntegrationTests` opens the bundled CC0 EPUB and extracts its metadata.

## Simulator and device behavior

- Launch on at least one current iPhone simulator and one physical iPhone.
- Import `minimal.epub` through Files and import a representative, legally owned reflowable EPUB. Verify a same-content EPUB renamed in Files is recognized as a duplicate.
- Confirm corrupt, unsupported, and DRM-protected files produce an error and no Library entry or permanent EPUB.
- Open an imported EPUB, page forward and backward, use chapter navigation, and confirm layout remains readable.
- Terminate and relaunch the app; confirm the exact last Readium Locator is restored.
- Select text and verify the custom selection toolbar appears in place (color dots, 笔记, 聊聊, 复制) and a color dot creates the highlight in one tap; verify handle adjustment re-anchors the toolbar.
- Tap an existing highlight and verify the highlight menu (recolor, 笔记, 删除 with undo pill) opens anchored to it.
- Create a note and verify its original selected-text Locator remains navigable.
- Reopen the publication and verify every persisted highlight is rendered in the expected color.
- Navigate from a persisted highlight back to its Locator.
- Rotate while reading and verify the current location does not jump unexpectedly.
- Background and foreground during reading; verify the embedded HTTP server resumes and the publication remains readable.
- Force-quit immediately after a location change, highlight, and note save; verify durable recovery.
- Remove an imported book from the Library. Confirm its EPUB, reading position, highlights, notes and preferences disappear together; reinstall/import again to confirm no stale file is reused.

## Highlight restoration integration point

`ReadiumReaderView.Coordinator.open(in:)` now performs the narrow bridge implementation immediately after `EPUBNavigatorViewController` creation:

1. It recreates every Readium `Locator` from the persisted, lossless Locator JSON.
2. It maps the persisted color to `Decoration.Style.highlight(tint:)`.
3. It calls `navigator.apply(decorations:in:)` in the `"highlights"` group, and reloads that group when the persisted highlights change.

This is code-complete only. Do not mark it verified from inspection or portable tests: successful iOS compilation plus visible rendering, interaction, and reopen tests are still required. If the installed Readium version reports unsupported decoration behavior, keep the persisted highlights and record the exact Navigator API behavior rather than silently discarding them.

## Gate result

Record the Xcode version, iOS SDK, simulator/device, commands, test result, any signing constraint, and any Readium/WKWebView warnings in the release checklist. Reader Foundation stays blocked while any item above is unverified.
