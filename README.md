<p align="center">
  <img src="logo.svg" alt="Elsepage" width="128" height="128">
</p>

<h1 align="center">Elsepage</h1>

<p align="center">
  <strong>An iOS reader for people who read to think — not just to finish books.</strong><br>
  Local-first. BYOK. Your words are the product; the book is the evidence.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-18%2B-5f6e5f?style=for-the-badge" alt="iOS 18+">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/Local%20first-No%20backend-9cb099?style=for-the-badge" alt="Local first">
  <img src="https://img.shields.io/badge/BYOK-Your%20key%2C%20your%20data-5f6e5f?style=for-the-badge" alt="BYOK">
  <img src="https://img.shields.io/badge/tests-123%20passing-9cb099?style=for-the-badge" alt="123 tests">
</p>

<p align="center">
  <a href="#why-elsepage">Why</a> ·
  <a href="#what-you-get">What you get</a> ·
  <a href="#hard-lines-we-wont-cross">Hard lines</a> ·
  <a href="#status">Status</a> ·
  <a href="#build-from-source">Build</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#contributing">Contributing</a>
</p>

---

Elsepage is a **native iOS EPUB reader with a personal thinking loop**: read, end a session, say what it made you think — text or voice — keep the words on-device, and when you want, get a grounded AI response that cites the book instead of generic ChatGPT glow.

It does **not** own your progress bar and call it a day. It does not summarize the book for you by default. It does not phone home.

> **Bring your own key (BYOK).** Provider-agnostic — OpenAI, DeepSeek, Gemini-compatible, or Anthropic behind one small `ModelClient` contract. The key lives only in Keychain. No Elsepage backend, no account, no cloud vector database.

---

## Why Elsepage?

Reading apps fail in two boring ways:

1. **Finish the book, get nothing.** The app tracks progress, streaks, and "completed" — and the two minutes after closing the book, the part that actually makes a book yours, is left to evaporate.
2. **AI summary machines.** The book gets digested before you've formed a view, so the reading is outsourced and your own thoughts never get to exist.

Elsepage is built so both stay rare:

| Pillar | What it means in practice |
|--------|---------------------------|
| **Your words are first-class** | The raw reflection is saved before any AI touch and is never overwritten (PRD P2). |
| **Local-first to the core** | EPUB, highlights, reflections and the SQLite store live on your device. Reading and reflecting work with no network. |
| **Grounded AI** | Agent replies carry clickable citations that jump back to the exact passage — not "trust me, I read it". |
| **BYOK, provider-agnostic** | One `ModelClient` interface; swap OpenAI / DeepSeek / Gemini / Anthropic without touching the loop. |
| **Voice that's actually usable** | Tap-to-talk or hold-to-talk, live editable transcription, optional MP3, and one-tap AI polish that keeps your meaning. |
| **Thinking is the product** | Session context, same-book past thoughts, and a structured Journal — the book is evidence, not the end. |

If you want an iOS reader that treats **what you thought** as the deliverable, you're in the right repo.

---

## What you get

### The reading loop

- **Real EPUB reading** — Readium engine; stable position, highlights, notes, search.
- **Explicit session end** — "这一段约 N 分钟", then an invitation to leave something behind.
- **Reflection that saves first** — raw text/voice is persisted locally before any network work; an AI failure never loses your words.
- **A grounded Agent** — knows what you just read (session context), can retrieve the current book, connects past thoughts from the same book, and cites evidence you can tap back to the page.

### Voice

- **Tap-to-talk or hold-to-talk**, with live (partial) transcription you can edit.
- **Optional audio file** — MP3 on device, AAC fallback on the simulator.
- **One-tap AI polish** — tidies your spoken words without changing meaning; the raw words stay stored.

### Journal & transparency

- **Structured Journal** — session duration, chapters, linked highlights, what you think, open questions, citations.
- **Router transparency** — every reply records the proposed vs validated context plan, fallback cause, and per-stage timing; the UI tells you "this used N passages of what you've read".

### Hard lines we won't cross

- No Elsepage backend, account, or cloud vector database
- No default "summarize the whole book" behavior
- No overwriting your original expression with AI output
- No API keys outside Keychain
- No reflection leaves your device except to the provider you explicitly chose

---

## Status

A real product loop, not a demo: read → reflect → save → grounded reply → Journal work end-to-end, **123 tests green**, and an unsigned iOS build gate passes.

| Area | State |
|------|-------|
| Reader foundation | ~85% |
| Reflection loop | ~70% |
| Book context / Agent | ~60% (citations now grounded and locally verified) |
| Voice reflection | shipped: hold/tap, MP3, AI polish |
| Memory / personal context | early — the next phase |
| Habit / onboarding / release polish | early |

Open backlog and ideas: [Issues](https://github.com/freecodetiger/Elsepage/issues).

---

## Build from source

### Requirements

| Tool | Notes |
|------|--------|
| **Xcode 16+** | iOS 18 SDK |
| **XcodeGen** | `brew install xcodegen` |
| **Readium** | resolved as an Xcode package (`swift-toolkit` 3.3.0) |

```bash
xcodegen generate
open ReadLoop.xcodeproj    # resolve packages, run the ReadLoop scheme
```

The portable suite needs no Xcode:

```bash
swift test                 # 123 tests
```

A device/simulator run needs the full Xcode install — Readium's navigator is UIKit-based. Manual-device checks are tracked in `docs/READER_FOUNDATION_XCODE_GATE.md`.

---

## Architecture

One loop. One owner per concern.

```text
EPUB
  → Readium                  book rendering, positions, highlights, search
  → ReadingSessionService    explicit session lifecycle ("这一段约 N 分钟")
  → Reflection + Evidence    your words, saved first (locator / session / highlights)
  → Context Routing          what the Agent may use: proposed plan → validated plan
  → ReaderAgent              grounded reply, locally verified citations, disclosure
  → Journal / Thoughts       what survives the two minutes after the book
```

| Concern | Owner |
|---------|--------|
| EPUB / reading | `ReaderCore` + Readium |
| Session lifecycle | `ReadingSessionCore` |
| Reflection & evidence | `ReflectionCore` + `Persistence` |
| Local book retrieval | `RetrievalCore` (lexical FTS + ranker, all local) |
| Context routing | `ContextRouting` (proposed vs validated, fallback) |
| Agent runtime | `AgentRuntime` / `ReaderAgent` |
| Voice | `SpeechCore` (system Speech, MP3/AAC) |
| AI polish | `TranscriptPolishService` (standalone, BYOK) |
| Providers | `ModelProviders` (one `ModelClient` contract) |

```text
Sources/
  ReaderCore / ReadingSessionCore / ReflectionCore   domain
  RetrievalCore                                      local book retrieval
  ContextRouting / ReaderAgent / AgentRuntime        the thinking loop
  ModelProviders / SpeechCore                        BYOK providers & voice
  Persistence / LibraryCore / AppInfrastructure      storage & app plumbing

App/     SwiftUI: Reader, Today, Thoughts (Journal), Reflection, Settings
Tests/   swift-testing (123 tests)
```

---

## Contributing

**Contributions are welcome** — from a repro for a reader edge case to the Memory phase.

| You care about… | Jump in on… |
|-----------------|-------------|
| Reader reliability | Long-book performance, rotation, VoiceOver, background restore |
| The reflection loop | Journal structure, voice flow, polish quality |
| Grounded AI | Citation UX, session context, router transparency |
| Memory (next phase) | Evidence-backed personal context — not bolted onto `ReflectionRepository` |
| Docs & onboarding | The honest gaps in this README, build tips, screenshots |

### PR checklist

```bash
swift test                                  # portable suite
xcodegen generate && xcodebuild …           # App-layer changes
```

In the description: **user-visible behavior**, **layer touched**, **how you verified** (portable tests vs device gate). Commits: Conventional Commits.

---

## Community

- [Issues](https://github.com/freecodetiger/Elsepage/issues) — bugs & ideas
- ⭐ **Star the repo** if Elsepage is your thinking reader — it helps the next person find it.

<p align="center">
  <a href="https://github.com/freecodetiger/Elsepage/stargazers"><strong>Star</strong></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/freecodetiger/Elsepage/issues/new"><strong>Report / request</strong></a>
</p>

---

## License

License file not yet published. Engineering codename: **ReadLoop** · App title: **Reader** · Product: **Elsepage**.

---

<p align="center">
  <sub>
    Swift 6 · Readium · local-first · made for the two minutes after the book<br>
    中文界面 · English docs for the global community
  </sub>
</p>
