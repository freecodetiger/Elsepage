# README and contributor guide — complete

Date: 2026-10-22. Baseline: `main@7b8623a`. GSD quick initialized; specialized agents unavailable, executed inline.

## Delivered

- Refreshed the English README with the product loop, current implemented features, explicit AI data flow, on-device speech requirements, active-development status, setup, module map, contribution entry and documentation links.
- Removed unsupported completion percentages, stale Memory/onboarding claims and the placeholder xcodebuild PR command. Kept implementation distinct from device/provider acceptance.
- Added root Chinese `CONTRIBUTING.md` for contribution opportunities, issue reports, forks/branches/PRs, product invariants, scoped verification, credential/data hygiene, real authorship, and contribution under existing GPL-3.0-only terms.
- Linked the guide from `docs/DEVELOPMENT.md`. Did not edit AGENTS.md or CLAUDE.md policies, source, build configuration, pins, or license text.

## Verification

- README: 44 local references/anchors; CONTRIBUTING: 9; development guide: 10. All 63 resolve.
- Documented four package test targets, macOS 14 platform, GRDB 7.11.1 and Readium 3.11.0 match actual manifests/configuration; DEBUG Python test entry exists.
- LICENSE SHA-256 remains `fb981668c18a279e285fc4d83fba1e836cc84dd4daa73c9697d3cfd2d8aca6e0`; no extra licensing exceptions or restrictions introduced.
- Confirmed no diffs in App, Sources, Tests, Scripts, Fixtures, LICENSE, package configuration/pins or Xcode inputs. Removed stale README completion/test claims.
- `git diff --check` passed; repeat staged whitespace/scope check before commit.
- Documentation-only change: no Swift tests, Xcode generation/builds, simulator/device operations or Provider calls; no remote push.
