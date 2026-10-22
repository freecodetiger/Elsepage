<p align="center">
  <img src="docs/assets/branding/logo-transparent.png" alt="Elsepage logo" width="128" height="128">
</p>

<h1 align="center">Elsepage · 页外</h1>

<p align="center">
  <strong>Read, reflect, and build a record of how you think.</strong><br>
  让阅读留下自己的思考。<br>
  Native iOS · Local-first · Bring your own AI key
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-18%2B-5f6e5f?style=flat-square" alt="iOS 18+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square" alt="Swift 6">
  <img src="https://img.shields.io/badge/license-GPL--3.0-5f6e5f?style=flat-square" alt="GPL-3.0 license">
</p>

<p align="center">
  <a href="#the-idea">The idea</a> ·
  <a href="#features">Features</a> ·
  <a href="#project-status">Status</a> ·
  <a href="#build-from-source">Build</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#contributing">Contributing</a> ·
  <a href="#license">License</a>
</p>

## The idea

Elsepage is an open-source iOS EPUB reader and personal thinking companion. Read a passage, write or speak what it brings to mind, and invite an AI response grounded in your reading and past reflections. Over time, those entries become a personal archive of ideas, questions, and changes in perspective.

Your original reflection is saved locally before an AI reply is requested. AI feedback, summaries, and personal memory are derived records; your own words remain the foundation.

The interface is primarily Chinese. **ReadLoop** is the engineering name used by the Swift package and Xcode project.

## Features

| Area | Current implementation |
| --- | --- |
| EPUB reading | Readium-based reader, reading position restoration, themes, highlights, notes, search, and user-initiated passage help. |
| Reflection | Text and voice input after reading, local save, follow-up discussion, and retry for a missing Agent reply. |
| Voice | On-device `zh-CN` recognition, editable partial transcripts, optional saved audio with playback, and separate BYOK text polish. Recognition requires an available on-device model. |
| Grounded feedback | Reading-session context, book evidence retrieval, links to cited passages, and connections to past reflections. |
| Personal Brain | Thoughts, questions, and memories with source evidence, revisions, editing, and deletion. |
| Data control | Local book/data storage, export, and deletion controls. App API keys are stored in Keychain. |

### AI and privacy

- Reading and saving text reflections work without a model connection.
- AI features use your own provider configuration and key. Provider presets include OpenAI, DeepSeek, Anthropic, and Gemini through their respective adapters; custom OpenAI-compatible endpoints are supported.
- Chat, optional embedding, and reranking requests go directly to configured providers. Requests can contain relevant book excerpts, reflections, and personal context. Those providers' policies apply to the data they receive.
- Elsepage has no proprietary backend or required Elsepage account. The current Chat adapters use non-streaming HTTP responses.
- The Agent stays quiet during reading unless you invoke it. See the [product requirements](ReadLoop_PRD.md) for the full product invariants and accepted implementation deviations.

## Project status

**Under active development.** The reading → reflection → saved response → journal flow and the Personal Brain domain are implemented. Implementation does not imply that every device, provider, or failure path has passed acceptance.

Current verification and release gaps are recorded in:

- [DEBUG test loop](docs/DEBUG-LOOP.md): available device scenarios and their limits; full application E2E automation is still incomplete.
- [Launch readiness](.planning/LAUNCH-READINESS.md): release work and outstanding acceptance items.
- [Provider verification matrix](docs/providers/VERIFICATION-MATRIX.md): live provider checks requiring real keys.

Test counts and completion percentages are intentionally not fixed in this README. Check the results for the commit you are reviewing.

## Build from source

### Requirements

| Tool | Requirement |
| --- | --- |
| macOS / Swift | Swift 6; portable package targets declare macOS 14+. |
| Xcode | Xcode 16+ with the iOS 18 SDK for the iOS App target. |
| XcodeGen | Install with `brew install xcodegen`. |
| Dependencies | GRDB 7.11.1 and Readium 3.11.0, pinned in [Package.swift](Package.swift) and [project.yml](project.yml). Initial dependency resolution needs network access. |

```sh
git clone https://github.com/freecodetiger/Elsepage.git
cd Elsepage
swift test
```

`swift test` runs the four package test targets. It does **not** compile `App/` or run the Readium iOS integration tests. It may rewrite `Package.resolved`; record its state before testing and preserve existing changes when reviewing dependency-pin differences.

For a human developer building the iOS App:

```sh
xcodegen generate
open ReadLoop.xcodeproj
```

Select your signing team, resolve packages, and run the `ReadLoop` scheme. Keep personal signing settings out of shared commits. Configure a provider in the App to try AI feedback; a real API key is not needed for the portable test suite.

See the [development guide](docs/DEVELOPMENT.md) for environment details and the [contribution guide](CONTRIBUTING.md) for verification responsibilities.

## Architecture

```text
EPUB → Readium → reading session → locally saved reflection
                                      ↓
                         context planning and validation
                                      ↓
                      retrieval, ranking, and context assembly
                                      ↓
                         bounded Agent execution → saved reply
                                      ↓
                          journal and Brain maintenance
```

| Code | Responsibility |
| --- | --- |
| [App/](App/) | SwiftUI screens, dependency assembly, Readium integration, and DEBUG diagnostics. |
| [ReaderCore](Sources/ReaderCore/) / [ReadingSessionCore](Sources/ReadingSessionCore/) | Reading locations, annotations, and sessions. |
| [ReflectionCore](Sources/ReflectionCore/) / [BrainCore](Sources/BrainCore/) | Original reflections, journal records, thoughts, questions, and memories. |
| [RetrievalCore](Sources/RetrievalCore/) | Book indexing, lexical/semantic retrieval, optional reranking, bounded evidence expansion, and reading-boundary checks. |
| [ContextRouting](Sources/ContextRouting/) / [ContextEngineering](Sources/ContextEngineering/) | Model-proposed context needs, deterministic policy, candidate ranking, and context budgets. |
| [ReaderAgent](Sources/ReaderAgent/) / [AgentRuntime](Sources/AgentRuntime/) | Product workflow and bounded model-call execution. |
| [ModelProviders](Sources/ModelProviders/) / [Persistence](Sources/Persistence/) | BYOK adapters, Keychain secret storage, and GRDB persistence. |
| [SpeechCore](Sources/SpeechCore/) / [AppInfrastructure](Sources/AppInfrastructure/) | Speech recognition, file handling, and shared App services. |
| [BenchCore](Sources/BenchCore/) | Agent evaluation and regression comparison CLI. |

The Agent orchestrates routing, retrieval, replies, and derived records. Model calls run with explicit budgets; citations and proposed Brain changes are checked by code.

[ARCHITECTURE.md](ARCHITECTURE.md) is a historical Agent architecture snapshot. Use it with current source and the relevant [feature specifications](docs/), rather than treating every old diagram or plan as current behavior.

## Contributing

Contributions are welcome: reproducible bugs, documentation, accessibility improvements, reader reliability, reflection UX, retrieval quality, and evidence-backed personal memory.

**Start with [CONTRIBUTING.md](CONTRIBUTING.md) / [贡献指南](CONTRIBUTING.md).** Issues and PRs may be written in Chinese or English.

1. Open an [issue](https://github.com/freecodetiger/Elsepage/issues) for a bug or discuss a substantial feature before implementation. Small fixes can go straight to a PR.
2. Work on a focused branch in your fork, or a repository branch if you have write access.
3. Run checks appropriate to the change and state what was actually verified. Package tests, device scenarios, and manual acceptance have different coverage.
4. Open a [pull request](https://github.com/freecodetiger/Elsepage/pulls) targeting `main`, describing the problem, resulting behavior, and validation evidence.

For priorities, follow the PRD:

> Reflection Quality > Memory Quality > Reader Agent Quality > Habit Loop > Reader Feature Breadth

Contributions are provided under the project's GPL-3.0-only license. Preserve existing copyright notices and third-party license information.

## Documentation

- [Development and repository map](docs/DEVELOPMENT.md)
- [Product requirements and implementation deviations](ReadLoop_PRD.md)
- [DEBUG verification workflow](docs/DEBUG-LOOP.md)
- [ReaderAgent Bench](docs/bench/README.md) and [regression requirements](docs/bench/REGRESSION.md)
- [Release acceptance checklist](docs/release/UAT-CHECKLIST.md)
- [Historical UI prototypes](docs/prototypes/README.md) and [brand assets](docs/assets/branding/README.md)

## License

Copyright (C) 2026 freecodetiger and contributors.

Licensed under the unmodified [GNU General Public License, version 3](LICENSE) (`GPL-3.0-only`), without additional exceptions or restrictions. Separately licensed files and third-party dependencies retain their respective licenses.
