# Privacy Policy

> Status: pre-release (Phase 10 / REL-01 final text)
> Before submission: render this document as a web page hosted at a publicly accessible URL, fill in the contact email and effective date, and enter that URL in App Store Connect's "Privacy Policy URL" field. Remove this block once hosted.
> Effective date: [DATE]
> Contact: [CONTACT EMAIL]

"ReadLoop" (working display name; "the App") is a personal thinking tool built around reading: a local-first EPUB reader combined with AI you configure yourself (BYOK, Bring Your Own Key) and a local agent runtime running on your device.

This policy describes honestly what the App does — and does not do — with your data. We have written it in plain language. If anything is unclear, contact us using the address above.

## 1. Where your data lives: entirely on your device

The following data is stored **only in your device's local storage**. We operate no servers that could receive it:

- The EPUB files you import;
- Your reading progress and positions;
- Reading session records (duration, start/end location);
- Highlights and notes;
- Your reflections (spoken or typed) and their transcripts;
- Your conversations with the agent;
- Your reading journal;
- The long-term memory and "reader profile" the agent builds for you;
- The full-text / vector index built locally for retrieval;
- Reading preferences, streaks, and achievements;
- Local diagnostics and request traces (for your own inspection in Settings).

## 2. API key storage

AI features require you to bring your own API key from a model provider (BYOK).

- The key is stored **only in the iOS Keychain**, marked as accessible "when unlocked, this device only";
- The key is never written to the database, to preference files, or to logs;
- The database stores only a reference to the keychain item, never the key itself;
- You can delete the key in Settings at any time, or together with "Clear All Local Data".

## 3. What leaves your device

**Day to day: nothing.** Reading, highlighting, writing reflections, taking notes, and browsing history all work locally and require no network.

Data leaves your device in **exactly one situation**: you have configured your own AI provider, and you actively trigger an AI request (for example, asking for agent feedback on a reflection, or starting a discussion).

In that case, the App sends the context **necessary** for that single request to the provider address **you chose**:

- A short excerpt of the text near your current reading position;
- A small number of relevant passages retrieved from the current book;
- Relevant excerpts of your own past reflections or memories, only when relevant to this request;
- The content of the current conversation.

Our commitments, matching the code:

- **The whole book is never sent.** Each request carries a strictly budgeted amount of context — only the necessary excerpts, truncated to that budget;
- **Unrelated history is never attached.** Past reflections or highlights that were not retrieved as relevant evidence are not included;
- You can always see in the App which content was used for a request (reflection evidence and local request traces);
- Requests go **directly from your device to that provider** — through none of our servers, because we have none.

**Speech-to-text** uses the speech recognition capability provided by Apple's operating system and is subject to Apple's privacy policy. What the App keeps is the transcript (and the raw audio file, if you chose to save it), stored locally.

## 4. What we do not do

- No accounts, no sign-up;
- No ReadLoop-operated servers receiving your data;
- No analytics, telemetry, advertising, or crash-reporting SDKs built in;
- No device identifiers for tracking, no cross-app tracking;
- No selling, renting, or sharing of your data — we never have access to it;
- No book store and no pirated sources; books can only be imported by you (non-DRM EPUB).

## 5. Third-party AI providers

When you use AI features, the content sent to your provider (Section 3) is governed by **that provider's own privacy policy and terms**. Please read the policy of the provider you choose.

Presets included in the App (any OpenAI-compatible endpoint also works): OpenAI, Anthropic, DeepSeek, Google Gemini, OpenRouter, Groq, Mistral, xAI, SiliconFlow, Moonshot, Alibaba Cloud Bailian, Zhipu.

Switching providers or deleting your key never loses any local reading data or memory.

## 6. Your control over your data

In "Settings → Data & Privacy" you can:

- **Export My Data**: export all of your personal data (books, reading positions, highlights, notes, reflections, long-term memory, your reader profile, etc.) as a JSON file to keep or migrate. The export matches what you see in the App and **excludes** provider configuration and API keys;
- **Delete a single book**, including its progress, highlights, notes, reflections, and index;
- **Clear All Local Data**: after a two-step confirmation, delete every book and file, the index, progress, highlights, notes, sessions, reflections, journal, memories, achievements, provider configuration, the keychain keys, and the App's own preferences — returning the App to first-launch state;
- **Delete the App**: uninstalling removes all local data (keychain items included).

You can also view, edit, and delete agent memories in "My Mind" at any time, and remove individual provider configurations in Settings.

## 7. Children

The App collects no data at all (everything stays on the user's device, as described above), so no personal information is collected from anyone, including children. Use by minors should be supervised by a parent or guardian.

## 8. Changes to this policy

If we ever introduce a feature that would change the commitments above (for example, optional cloud sync), we will update this policy and clearly announce it in the App before it takes effect. Current version: all data local, nothing collected.

## 9. Contact us

Questions about this policy or how data flows:

- Email: [CONTACT EMAIL]
