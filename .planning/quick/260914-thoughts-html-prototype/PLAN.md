# Thoughts HTML Prototype

## Goal

Create a realistic, interactive HTML prototype for the redesigned 想法 page.
The prototype demonstrates the subtraction pass: every reading record has an AI
response, so no "有回应" state or "请 AI 回复" action appears.

## Deliverable

- `docs/prototypes/thoughts-redesign.html`
- Desktop presentation stage with realistic iPhone frames.
- Mobile responsive presentation.
- Interactive 记录 / 档案 segmented control.
- Expandable record card with 我的原话 / AI 回应 / 更多依据.
- All dates rendered in Chinese formats such as 9月14日.

## Design constraints

- Neutral black/white visual system.
- Page background, card surface and secondary AI surface must be visibly distinct.
- One primary tap target per collapsed card; no status-chip wall.
- Expand only after user intent.
- No "有回应", no "请 AI 回复", no green brand accent.
- Keep reader/book content feeling editorial rather than like a dashboard.

## Verification

- Open the HTML in a browser.
- Confirm no English month names appear.
- Confirm the 记录 / 档案 toggle and card disclosure work.
- Confirm the mobile width remains usable.
