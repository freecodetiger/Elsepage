# ReadLoop Reader Foundation

ReadLoop is the engineering codename. This repository implements a local-first iOS EPUB reader foundation plus the first text-only reading-session and reflection loop described by the product and technical Source of Truth documents.

## Open the project

1. Install Xcode with the iOS 18 SDK and select it with `xcode-select`.
2. Install XcodeGen (`brew install xcodegen`).
3. Run `xcodegen generate`, then open `ReadLoop.xcodeproj`.
4. Resolve Swift packages and run the `ReadLoop` scheme.

The app has no account or product backend requirement. Imported EPUBs and `readloop.sqlite` live under Application Support. Reading and raw text reflection work without a network or AI provider. The repository includes a Keychain-only BYOK provider foundation; provider setup and in-app Agent delivery are not yet wired.

## Verification

Run `swift test` for migrations, book identity, import deduplication, Locator persistence, and Highlight/Note relationship tests. The iOS integration additionally requires a full Xcode installation with an installed iOS platform because Readium's navigator is UIKit-based.

The purpose-built CC0 EPUB fixture can be reproduced with `Scripts/build-test-epub.sh`. Full iOS verification requirements are recorded in `docs/READER_FOUNDATION_XCODE_GATE.md` and remain a release gate.

## Source of Truth

- `ReadLoop_PRD.md`
- `ReadLoop_Technical_Design.md`

The current product loop is deliberately small: read, explicitly end a session, save a raw text reflection locally, then revisit it in Thoughts. Agent responses, provider settings, Memory, and RAG remain incomplete phases.
