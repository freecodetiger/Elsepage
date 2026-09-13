# Conversation Identity Settings

## Goal

Add a Settings surface for the user and assistant identities already consumed by
conversation messages.

## Deliverable

- New `对话身份` settings page.
- Editable user display name and assistant display name.
- Selectable symbol-based avatars for both identities.
- Real-time inline preview using the same avatar/name/body pattern.
- Reset to defaults.
- Settings root link with current identity summary.

## Preferences

- `profile.userDisplayName`
- `profile.assistantDisplayName`
- `profile.userAvatarSymbol`
- `profile.assistantAvatarSymbol`

## Verification

- XcodeGen includes the new App file.
- App Swift files parse.
- Existing `swift test` suite remains green.
