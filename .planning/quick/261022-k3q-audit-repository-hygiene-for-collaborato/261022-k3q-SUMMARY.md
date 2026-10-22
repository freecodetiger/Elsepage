# Repository hygiene — complete

Date: 2026-10-22. Baseline: `main@84d2e09`. GSD specialized agents were unavailable; executed inline after quick initialization.

## Changes

- Removed root `logo-fullbleed.png`, byte-identical to the retained app marketing icon.
- Moved five unique brand assets to `docs/assets/branding/` and the historical root HTML to `docs/prototypes/`; added indexes and repaired references.
- Removed four untracked `.DS_Store` files and ignored `.build/` (1,875,148 KiB) / `DerivedData/` (3,095,324 KiB), after checking active build processes and absence of tracked contents.
- Corrected stale README dependency version, test-count/success assertions and Today directory description.
- Added `docs/DEVELOPMENT.md` and `docs/maintenance/repository-hygiene-2026-10-22.md` with file classification, preserved evidence, branch differences, document drift and credential-scan limitations.
- Preserved unique assets, AppIcon slots, source/test/build inputs, benchmark baselines, planning history, local agent tools/preferences and the ignored experiment EPUB.

## Verification

- Six moves compared byte-for-byte with baseline Git blobs; removed duplicate compared with retained icon.
- All 18 asset catalog filename entries exist.
- Swift/App/Tests/Fixtures/Scripts/package pins/project inputs have no diff from baseline.
- All 30 local links in six touched documentation files resolve; the moved HTML has no file resource references.
- Common credential shapes and sensitive filenames checked in tracked text files. Four loose matches were test placeholders/environment guidance; no real credential identified. Not a complete history/security audit.
- Both ignored caches are absent; local preferences/tools/experimental EPUB remain.
- `git diff --check` passed before final staging; repeat staged check before commit.
- No Swift tests, Xcode, simulator/device work, Provider calls, fetch, push or branch merge. Documentation and ignored-cache maintenance do not validate application runtime behavior.

## Follow-up decisions

Reconcile main/ragbench delivery scope, old active plan placement, document authority and stale progress, collaborative Git identity/signing conventions, and root licensing. Findings are documented; no speculative deletions or policy changes made.
