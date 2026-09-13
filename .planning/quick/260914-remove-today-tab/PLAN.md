# Remove Today Tab

## Goal

Remove `今天` as a top-level tab while preserving its two useful capabilities:

1. Next-action prompting moves to the top of 书架.
2. Reading/thinking streaks move to 我的.

## Required sequence

1. Update `ReadLoop_PRD.md` and `docs/UI_LANGUAGE_AND_IA_SPEC.md`.
2. Refactor Today state/model into a reusable next-action surface owned by Library.
3. Remove Today from AppShell and make Library the default tab.
4. Move streak derivation/display to My Mind.
5. Keep the missing-Reflection recovery path, including explicit dismissal.
6. Run `swift test`, parse changed App files, and restore `Package.resolved` if needed.

## Acceptance

- Bottom navigation is `书架 / 想法 / 我的`.
- App opens on 书架.
- Pending Reflection is visible at the top of 书架 and can open the existing reflection sheet.
- If no next action exists, 书架 remains a clean book library.
- Reading/thinking streaks are visible in 我的.
- No user-facing `今天` tab remains.
